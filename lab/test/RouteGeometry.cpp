#include "../../native/RouteGeometry.hpp"

#include <cassert>

int main() {
  const auto points = reactnativemaps::prepareRoute("_p~iF~ps|U_ulLnnqC_mqNvxq`@", 0);
  assert(points.size() == 3);
  assert(points[0].latitude == 38.5 && points[0].longitude == -120.2);
  const auto simplified = reactnativemaps::prepareRoute("_p~iF~ps|U_ulLnnqC_mqNvxq`@", 1000000);
  assert(simplified.size() == 2);
  try {
    reactnativemaps::prepareRoute("_", 0);
    assert(false);
  } catch (const std::invalid_argument&) {
  }
}
