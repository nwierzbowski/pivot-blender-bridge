#pragma once

#include <cmath>
// #include <cstdint>

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;

    bool operator<(const Vec3 &other) const {
            return x < other.x || (x == other.x && y < other.y) || (x == other.x && y == other.y && z < other.z);
        }

        Vec3 operator-(const Vec3& other) const {
        return {x - other.x, y - other.y, z - other.z};
        }

        Vec3 operator+(const Vec3& other) const {
            return {x + other.x, y + other.y, z + other.z};
        }
        
        Vec3 operator*(float scale) const {
            return {x * scale, y * scale, z * scale};
        }
        
        float dot(const Vec3& other) const {
            return x * other.x + y * other.y + z * other.z;
        }
        
        Vec3 cross(const Vec3& other) const {
            return Vec3{
                y * other.z - z * other.y,
                z * other.x - x * other.z,
                x * other.y - y * other.x
            };
        }
        
        float length_squared() const {
            return x * x + y * y + z * z;
        }
        
        float length() const {
            return std::sqrt(length_squared());
        }
        
        Vec3 normalized() const {
            float len = length();
            return len > 0 ? Vec3{x / len, y / len, z / len} : Vec3{0, 0, 0};
        }
};

struct Vec2 { 
        float x = 0.0f, y = 0.0f; 
        
        bool operator<(const Vec2 &other) const {
            return x < other.x || (x == other.x && y < other.y);
        }

        Vec2 operator-(const Vec2& other) const {
        return {x - other.x, y - other.y};
        }
        
        Vec2 operator+(const Vec2& other) const {
            return {x + other.x, y + other.y};
        }
        
        Vec2 operator*(float scale) const {
            return {x * scale, y * scale};
        }
        
        float dot(const Vec2& other) const {
            return x * other.x + y * other.y;
        }
        
        float cross(const Vec2& other) const {
            return x * other.y - y * other.x;
        }
        
        float length_squared() const {
            return x * x + y * y;
        }
        
        float length() const {
            return std::sqrt(length_squared());
        }
        
        Vec2 normalized() const {
            float len = length();
            return len > 0 ? Vec2{x / len, y / len} : Vec2{0, 0};
        }
    };

struct BoundingBox {
    Vec3 min_corner;
    Vec3 max_corner;
    float volume;
    float rotation_angle;  // Radians

    BoundingBox() : volume(std::numeric_limits<float>::max()), rotation_angle(0) {}
};