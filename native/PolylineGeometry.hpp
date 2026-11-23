#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

namespace rnmaps::polyline {

struct Coordinate {
  double latitude;
  double longitude;
};

namespace detail {

inline constexpr double kEarthRadiusMeters = 6371008.8;
inline constexpr std::size_t kMaxChunks = 7;
inline constexpr double kPi = 3.14159265358979323846;

struct Point {
  double x;
  double y;
};

inline std::optional<std::int64_t> decodeValue(std::string_view encoded, std::size_t &index) {
  std::int64_t result = 0;
  int shift = 0;
  for (std::size_t start = index; index < encoded.size(); ++index) {
    const int chunk = static_cast<unsigned char>(encoded[index]) - 63;
    if (chunk < 0 || chunk > 63 || index - start == kMaxChunks) {
      return std::nullopt;
    }
    result |= static_cast<std::int64_t>(chunk & 0x1f) << shift;
    shift += 5;
    if (chunk < 0x20) {
      ++index;
      return (result & 1) ? ~(result >> 1) : (result >> 1);
    }
  }
  return std::nullopt;
}

inline double toRadians(double degrees) {
  return degrees * kPi / 180;
}

inline std::vector<Point> project(const Coordinate *coordinates, std::size_t count) {
  const Coordinate origin = coordinates[0];
  const double scale = std::cos(toRadians(origin.latitude));
  std::vector<Point> points;
  points.reserve(count);
  for (std::size_t index = 0; index < count; ++index) {
    double longitudeDelta = coordinates[index].longitude - origin.longitude;
    if (longitudeDelta > 180) {
      longitudeDelta -= 360;
    } else if (longitudeDelta < -180) {
      longitudeDelta += 360;
    }
    points.push_back({kEarthRadiusMeters * toRadians(longitudeDelta) * scale,
                      kEarthRadiusMeters * toRadians(coordinates[index].latitude - origin.latitude)});
  }
  return points;
}

inline double segmentDistance(Point p, Point a, Point b) {
  const double dx = b.x - a.x;
  const double dy = b.y - a.y;
  const double lengthSquared = dx * dx + dy * dy;
  double t = 0;
  if (lengthSquared > 0) {
    t = std::min(1.0, std::max(0.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared));
  }
  const double ex = p.x - (a.x + t * dx);
  const double ey = p.y - (a.y + t * dy);
  return std::sqrt(ex * ex + ey * ey);
}

} // namespace detail

inline std::optional<std::vector<Coordinate>> decode(std::string_view encoded) {
  std::vector<Coordinate> coordinates;
  std::int64_t latitude = 0;
  std::int64_t longitude = 0;
  std::size_t index = 0;
  while (index < encoded.size()) {
    const auto latitudeDelta = detail::decodeValue(encoded, index);
    if (!latitudeDelta) {
      return std::nullopt;
    }
    const auto longitudeDelta = detail::decodeValue(encoded, index);
    if (!longitudeDelta) {
      return std::nullopt;
    }
    latitude += *latitudeDelta;
    longitude += *longitudeDelta;
    coordinates.push_back({static_cast<double>(latitude) / 1e5, static_cast<double>(longitude) / 1e5});
  }
  return coordinates;
}

inline std::vector<Coordinate> simplify(const Coordinate *coordinates, std::size_t count, double toleranceMeters) {
  if (count < 3 || toleranceMeters <= 0) {
    return std::vector<Coordinate>(coordinates, coordinates + count);
  }
  const std::vector<detail::Point> points = detail::project(coordinates, count);
  std::vector<bool> keep(count, false);
  keep.front() = true;
  keep.back() = true;
  std::vector<std::pair<std::size_t, std::size_t>> ranges{{0, count - 1}};
  while (!ranges.empty()) {
    const auto [first, last] = ranges.back();
    ranges.pop_back();
    std::size_t farthest = 0;
    double farthestDistance = toleranceMeters;
    for (std::size_t index = first + 1; index < last; ++index) {
      const double distance = detail::segmentDistance(points[index], points[first], points[last]);
      if (distance > farthestDistance) {
        farthest = index;
        farthestDistance = distance;
      }
    }
    if (farthest != 0) {
      keep[farthest] = true;
      ranges.emplace_back(first, farthest);
      ranges.emplace_back(farthest, last);
    }
  }
  std::vector<Coordinate> simplified;
  for (std::size_t index = 0; index < count; ++index) {
    if (keep[index]) {
      simplified.push_back(coordinates[index]);
    }
  }
  return simplified;
}

} // namespace rnmaps::polyline
