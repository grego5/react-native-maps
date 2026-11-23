package com.margelo.nitro.mapssession;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Finds the lines within their slop of a tap, in screen pixels. */
public final class PolylineHits {
  public static final class Candidate {
    final String id;
    final float[] points;
    final float slop;

    /** {@code points} holds x and y pairs. */
    public Candidate(String id, float[] points, float slop) {
      this.id = id;
      this.points = points;
      this.slop = slop;
    }
  }

  private static final class Hit {
    final String id;
    final double distance;

    Hit(String id, double distance) {
      this.id = id;
      this.distance = distance;
    }
  }

  private PolylineHits() {}

  /** Returns the ids of the candidates within slop of the tap, nearest first, then in candidate order. */
  public static List<String> find(List<Candidate> candidates, float x, float y) {
    List<Hit> hits = new ArrayList<>();
    for (Candidate candidate : candidates) {
      if (candidate.slop <= 0 || candidate.points.length < 2) {
        continue;
      }
      double distance = distance(candidate.points, x, y);
      if (distance <= candidate.slop) {
        hits.add(new Hit(candidate.id, distance));
      }
    }
    Collections.sort(hits, (a, b) -> Double.compare(a.distance, b.distance));
    List<String> ids = new ArrayList<>(hits.size());
    for (Hit hit : hits) {
      ids.add(hit.id);
    }
    return ids;
  }

  private static double distance(float[] points, float x, float y) {
    if (points.length < 4) {
      return Math.hypot(x - points[0], y - points[1]);
    }
    double nearest = Double.POSITIVE_INFINITY;
    for (int i = 0; i + 3 < points.length; i += 2) {
      nearest = Math.min(nearest, segmentDistance(points[i], points[i + 1], points[i + 2], points[i + 3], x, y));
    }
    return nearest;
  }

  private static double segmentDistance(double ax, double ay, double bx, double by, double x, double y) {
    double dx = bx - ax;
    double dy = by - ay;
    double lengthSquared = dx * dx + dy * dy;
    double t = lengthSquared == 0 ? 0 : ((x - ax) * dx + (y - ay) * dy) / lengthSquared;
    t = Math.max(0, Math.min(1, t));
    return Math.hypot(x - (ax + t * dx), y - (ay + t * dy));
  }
}
