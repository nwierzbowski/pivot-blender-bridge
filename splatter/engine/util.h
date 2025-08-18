#pragma once

#include <cmath>
// #include <cstdint>

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

struct PT { 
        float x, y; 
        // uint32_t idx;
        
        bool operator<(const PT &other) const {
            return x < other.x || (x == other.x && y < other.y);
        }

        PT operator-(const PT& other) const {
        return {x - other.x, y - other.y};
        }
        
        PT operator+(const PT& other) const {
            return {x + other.x, y + other.y};
        }
        
        PT operator*(float scale) const {
            return {x * scale, y * scale};
        }
        
        float dot(const PT& other) const {
            return x * other.x + y * other.y;
        }
        
        float cross(const PT& other) const {
            return x * other.y - y * other.x;
        }
        
        float length_squared() const {
            return x * x + y * y;
        }
        
        float length() const {
            return std::sqrt(length_squared());
        }
        
        PT normalized() const {
            float len = length();
            return len > 0 ? PT{x / len, y / len} : PT{0, 0};
        }
    };

struct BoundingBox {
    PT min_corner;
    PT max_corner;
    float area;
    PT center;
    float rotation_angle;  // Radians
    
    BoundingBox() : area(std::numeric_limits<float>::max()), rotation_angle(0) {}
};