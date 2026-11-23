#pragma once

#include "PolylineGeometry.hpp"

#include <cmath>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace reactnativemaps {

inline std::vector<rnmaps::polyline::Coordinate> prepareRoute(
    std::string_view encoded, double tolerance) {
  if (!std::isfinite(tolerance) || tolerance < 0) {
    throw std::invalid_argument("Polyline tolerance must be nonnegative and finite");
  }

  auto coordinates = rnmaps::polyline::decode(encoded);
  if (!coordinates || coordinates->size() < 2) {
    throw std::invalid_argument("An encoded route must contain at least two valid points");
  }
  for (const auto& point : *coordinates) {
    if (std::abs(point.latitude) > 90 || std::abs(point.longitude) > 180) {
      throw std::invalid_argument("Route coordinates are out of range");
    }
  }
  return rnmaps::polyline::simplify(coordinates->data(), coordinates->size(), tolerance);
}

} // namespace reactnativemaps
