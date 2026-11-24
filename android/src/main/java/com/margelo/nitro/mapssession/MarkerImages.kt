package com.margelo.nitro.mapssession

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.roundToInt

internal object MarkerImages {
  private const val maxImageBytes = 8 * 1024 * 1024
  private const val maxImageEdge = 1024
  private val main = Handler(Looper.getMainLooper())
  private val worker = Executors.newFixedThreadPool(2)
  private data class Key(val uri: String, val scale: Double, val density: Int)
  private val cache = object : LruCache<Key, Bitmap>(32 * 1024 * 1024) {
    override fun sizeOf(key: Key, value: Bitmap) = value.allocationByteCount
  }
  private val loading = mutableMapOf<Key, MutableList<(Result<Bitmap>) -> Unit>>()

  fun load(context: Context, image: MarkerImage, complete: (Result<Bitmap>) -> Unit) {
    val scale = image.scale ?: 1.0
    if (!scale.isFinite() || scale <= 0 || image.uri.isBlank()) {
      complete(Result.failure(IllegalArgumentException("Invalid marker image source")))
      return
    }
    val key = Key(image.uri, scale, context.resources.displayMetrics.densityDpi)
    cache.get(key)?.let {
      complete(Result.success(it))
      return
    }
    loading[key]?.let {
      it.add(complete)
      return
    }
    loading[key] = mutableListOf(complete)
    val application = context.applicationContext
    worker.execute {
      val result = runCatching { decode(application, key) }
      main.post {
        val callbacks = checkNotNull(loading.remove(key))
        result.getOrNull()?.let { cache.put(key, it) }
        callbacks.forEach { it(result) }
      }
    }
  }

  private fun decode(context: Context, key: Key): Bitmap {
    val uri = Uri.parse(key.uri)
    val bytes = when (uri.scheme) {
      "https", "http" -> {
        val connection = URL(key.uri).openConnection() as HttpURLConnection
        try {
          connection.connectTimeout = 15000
          connection.readTimeout = 15000
          check(connection.responseCode in 200..299) { "Marker image request failed (${connection.responseCode})" }
          connection.inputStream.use(::readImage)
        } finally {
          connection.disconnect()
        }
      }
      "file", "content" -> {
        val input = context.contentResolver.openInputStream(uri) ?: throw FileNotFoundException(key.uri)
        input.use(::readImage)
      }
      // Release builds resolve `require()` assets to bare resource names. Raw bytes keep density
      // buckets from rescaling the bitmap; `key.scale` already describes the chosen bucket.
      null -> {
        val resources = context.resources
        val id = resources.getIdentifier(key.uri, "drawable", context.packageName)
          .takeIf { it != 0 } ?: resources.getIdentifier(key.uri, "raw", context.packageName)
        if (id == 0) throw FileNotFoundException(key.uri)
        resources.openRawResource(id).use(::readImage)
      }
      else -> throw IllegalArgumentException("Unsupported marker image URI scheme")
    }

    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    check(options.outWidth > 0 && options.outHeight > 0) { "Cannot decode marker image" }
    val edge = maxOf(options.outWidth, options.outHeight)
    val displayScale = key.density / 160.0 / key.scale
    val displayEdge = (edge * displayScale).coerceIn(1.0, maxImageEdge.toDouble())
    val ratio = displayEdge / edge
    val width = (options.outWidth * ratio).roundToInt().coerceAtLeast(1)
    val height = (options.outHeight * ratio).roundToInt().coerceAtLeast(1)
    options.inJustDecodeBounds = false
    options.inSampleSize = Integer.highestOneBit((edge / displayEdge).toInt().coerceAtLeast(1))
    val decoded = checkNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)) {
      "Cannot decode marker image"
    }
    return Bitmap.createScaledBitmap(decoded, width, height, true).apply { density = key.density }
  }

  private fun readImage(input: InputStream): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
      val count = input.read(buffer)
      if (count < 0) return output.toByteArray()
      check(output.size() + count <= maxImageBytes) { "Marker image exceeds 8 MiB" }
      output.write(buffer, 0, count)
    }
  }
}
