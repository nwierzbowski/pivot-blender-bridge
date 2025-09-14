// Minimal JSON-over-stdin/stdout IPC loop with Boost.Interprocess shared memory for large data.
// Protocol: JSON control messages; large arrays via shared memory segments.
// Request: {"id":N, "op":"prepare", "shm_verts":"segment_name", "shm_edges":"segment_name", "vert_counts":[...], "edge_counts":[...]}
// Response: {"id":N, "ok":true, "rots":[...], "trans":[...]} or error.
// Shared memory: Python creates segments, engine maps them read-only, processes in-place.

#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <cstdint>
#include <optional>

#include "engine.h"

#if SPLATTER_HAVE_BOOST_IPC
#include <boost/interprocess/managed_shared_memory.hpp>
#endif

// Helper functions for JSON control
static std::vector<std::string> split_top_level_fields(const std::string &obj)
{
    std::vector<std::string> fields;
    int depth = 0;
    bool in_str = false;
    std::string cur;
    bool escape_next = false;
    bool started = false;
    for (char c : obj)
    {
        if (!started)
        {
            if (c == '{')
                started = true;
            continue;
        }
        if (in_str)
        {
            cur.push_back(c);
            if (escape_next)
            {
                escape_next = false;
                continue;
            }
            if (c == '\\')
            {
                escape_next = true;
                continue;
            }
            if (c == '"')
                in_str = false;
            continue;
        }
        switch (c)
        {
        case '"':
            in_str = true;
            cur.push_back(c);
            break;
        case '{':
        case '[':
            depth++;
            cur.push_back(c);
            break;
        case '}':
        case ']':
            depth--;
            cur.push_back(c);
            break;
        case ',':
            if (depth == 0)
            {
                fields.push_back(cur);
                cur.clear();
            }
            else
                cur.push_back(c);
            break;
        default:
            cur.push_back(c);
            break;
        }
    }
    if (!cur.empty())
        fields.push_back(cur);
    return fields;
}

static std::optional<std::string> get_value(const std::string &line, const std::string &key)
{
    auto fields = split_top_level_fields(line);
    std::string pat = "\"" + key + "\":";
    for (auto &f : fields)
    {
        auto pos = f.find(pat);
        if (pos != std::string::npos)
        {
            auto val = f.substr(pos + pat.size());
            auto start = val.find_first_not_of(" \t\r\n");
            if (start == std::string::npos)
                return std::string();
            auto end = val.find_last_not_of(" \t\r\n");
            return val.substr(start, end - start + 1);
        }
    }
    return std::nullopt;
}

static bool parse_uint_array(const std::string &jsonArr, std::vector<uint32_t> &out)
{
    if (jsonArr.empty())
        return false;
    size_t i = 0;
    while (i < jsonArr.size() && (jsonArr[i] == ' ' || jsonArr[i] == '\t'))
        ++i;
    if (i == jsonArr.size() || jsonArr[i] != '[')
        return false;
    ++i;
    std::string num;
    bool in_num = false;
    for (; i < jsonArr.size(); ++i)
    {
        char c = jsonArr[i];
        if ((c >= '0' && c <= '9'))
        {
            num.push_back(c);
            in_num = true;
        }
        else if (c == ',' || c == ']')
        {
            if (in_num)
            {
                unsigned long v = std::stoul(num);
                if (v > std::numeric_limits<uint32_t>::max())
                    return false;
                out.push_back(static_cast<uint32_t>(v));
                num.clear();
                in_num = false;
            }
            if (c == ']')
                break;
        }
        else if (c == ' ' || c == '\t')
        {
            // skip
        }
        else
            return false;
    }
    return true;
}

static void respond_error(int id, const std::string &msg)
{
    std::cout << '{' << "\"id\":" << id << ",\"ok\":false,\"error\":\"" << msg << "\"}" << std::endl;
}

int main(int argc, char **argv)
{
    std::cerr << "[engine] IPC server starting" << std::endl;
    std::string line;
    while (std::getline(std::cin, line))
    {
        if (line.empty())
            continue;
        if (line == "__quit__")
            break;
        auto idVal = get_value(line, "id");
        int id = idVal ? std::stoi(*idVal) : -1;
        auto opVal = get_value(line, "op");
        if (!opVal)
        {
            respond_error(id, "missing op");
            continue;
        }
        std::string op = *opVal;
        if (!op.empty() && op.front() == '"' && op.back() == '"')
            op = op.substr(1, op.size() - 2);

        try
        {
            if (op == "prepare")
            {
                std::string shm_verts, shm_edges;
                std::vector<uint32_t> vertCounts, edgeCounts;
                if (auto v = get_value(line, "shm_verts"))
                    shm_verts = *v;
                else
                {
                    respond_error(id, "missing shm_verts");
                    continue;
                }
                if (auto v = get_value(line, "shm_edges"))
                    shm_edges = *v;
                else
                {
                    respond_error(id, "missing shm_edges");
                    continue;
                }
                if (auto v = get_value(line, "vert_counts"))
                    parse_uint_array(*v, vertCounts);
                else
                {
                    respond_error(id, "missing vert_counts");
                    continue;
                }
                if (auto v = get_value(line, "edge_counts"))
                    parse_uint_array(*v, edgeCounts);
                else
                {
                    respond_error(id, "missing edge_counts");
                    continue;
                }
                uint32_t num_objects = static_cast<uint32_t>(vertCounts.size());
                if (num_objects == 0)
                {
                    std::cout << '{' << "\"id\":" << id << ",\"ok\":true,\"rots\":[],\"trans\":[]}" << std::endl;
                    continue;
                }
                if (edgeCounts.size() != num_objects)
                {
                    respond_error(id, "edge_counts size mismatch");
                    continue;
                }

#if SPLATTER_HAVE_BOOST_IPC
                boost::interprocess::managed_shared_memory verts_shm(boost::interprocess::open_only, shm_verts.c_str());
                boost::interprocess::managed_shared_memory edges_shm(boost::interprocess::open_only, shm_edges.c_str());
                const Vec3 *verts_ptr = verts_shm.find<Vec3>("verts").first;
                const uVec2i *edges_ptr = edges_shm.find<uVec2i>("edges").first;
                if (!verts_ptr || !edges_ptr)
                {
                    respond_error(id, "shared memory data not found");
                    continue;
                }

                std::vector<Quaternion> outR(num_objects);
                std::vector<Vec3> outT(num_objects);
                prepare_object_batch(verts_ptr, edges_ptr, vertCounts.data(), edgeCounts.data(), num_objects, outR.data(), outT.data());
                std::ostringstream rotsJson, transJson;
                rotsJson << '[';
                for (size_t i = 0; i < outR.size(); ++i)
                {
                    if (i)
                        rotsJson << ',';
                    rotsJson << '[' << outR[i].w << ',' << outR[i].x << ',' << outR[i].y << ',' << outR[i].z << ']';
                }
                rotsJson << ']';
                transJson << '[';
                for (size_t i = 0; i < outT.size(); ++i)
                {
                    if (i)
                        transJson << ',';
                    transJson << '[' << outT[i].x << ',' << outT[i].y << ',' << outT[i].z << ']';
                }
                transJson << ']';
                std::cout << '{' << "\"id\":" << id << ",\"ok\":true,\"rots\":" << rotsJson.str() << ",\"trans\":" << transJson.str() << '}' << std::endl;
#else
                respond_error(id, "Boost.Interprocess not available");
#endif
            }
            else
            {
                respond_error(id, "unknown op");
            }
        }
        catch (const std::exception &e)
        {
            respond_error(id, e.what());
        }
    }
    std::cerr << "[engine] IPC server exiting" << std::endl;
    return 0;
}