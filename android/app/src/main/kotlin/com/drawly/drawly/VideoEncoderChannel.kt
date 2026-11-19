package com.drawly.drawly

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * "drawly/video" method channel: H.264 MP4 encoding with the system MediaCodec
 * and MediaMuxer. Same methods as the Windows runner (available, begin,
 * addFrame, finish, abort). Encoding runs on a background thread.
 */
class VideoEncoderChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "drawly/video")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val writers = HashMap<Int, Mp4Writer>()
    private var nextId = 1

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "available") {
            result.success(true)
            return
        }
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "begin" -> {
                        val path = call.argument<String>("path")!!
                        val w = call.argument<Int>("width")!!
                        val h = call.argument<Int>("height")!!
                        val fps = call.argument<Int>("fps")!!
                        val bitrate = call.argument<Int>("bitrate") ?: 8_000_000
                        require(w > 0 && h > 0 && w % 2 == 0 && h % 2 == 0 && fps > 0) { "Invalid size (must be even) or fps" }
                        val id = nextId++
                        writers[id] = Mp4Writer(path, w, h, fps, bitrate)
                        id
                    }
                    "addFrame" -> {
                        writer(call).addFrame(call.argument<ByteArray>("rgba")!!)
                        null
                    }
                    "finish" -> {
                        val id = call.argument<Int>("id")!!
                        val ok = writers.remove(id)?.finish() ?: false
                        ok
                    }
                    "abort" -> {
                        writers.remove(call.argument<Int>("id")!!)?.abort()
                        null
                    }
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                call.argument<Int>("id")?.let { writers.remove(it)?.abort() }
                main.post { result.error("video", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun writer(call: MethodCall): Mp4Writer =
        writers[call.argument<Int>("id")!!] ?: throw IllegalStateException("Unknown video handle")
}

private class Mp4Writer(private val path: String, private val width: Int, private val height: Int, private val fps: Int, bitrate: Int) {
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private val muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var started = false
    private var frame = 0L

    init {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
    }

    fun addFrame(rgba: ByteArray) {
        require(rgba.size >= width * height * 4) { "Frame too small" }
        val index = dequeueInput()
        val image = codec.getInputImage(index) ?: throw IllegalStateException("No input image")
        val y = image.planes[0]
        val u = image.planes[1]
        val v = image.planes[2]
        val yBuf = y.buffer
        val uBuf = u.buffer
        val vBuf = v.buffer
        for (row in 0 until height) {
            for (col in 0 until width) {
                val i = (row * width + col) * 4
                val r = rgba[i].toInt() and 0xFF
                val g = rgba[i + 1].toInt() and 0xFF
                val b = rgba[i + 2].toInt() and 0xFF
                yBuf.put(row * y.rowStride + col * y.pixelStride, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                if (row % 2 == 0 && col % 2 == 0) {
                    val cr = row / 2
                    val cc = col / 2
                    uBuf.put(cr * u.rowStride + cc * u.pixelStride, (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte())
                    vBuf.put(cr * v.rowStride + cc * v.pixelStride, (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte())
                }
            }
        }
        codec.queueInputBuffer(index, 0, width * height * 3 / 2, frame * 1_000_000L / fps, 0)
        frame++
        drain(false)
    }

    private fun dequeueInput(): Int {
        while (true) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) return index
            drain(false)
        }
    }

    private fun drain(endOfStream: Boolean) {
        while (true) {
            val index = codec.dequeueOutputBuffer(info, 10_000)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!endOfStream) return
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    started = true
                }
                index >= 0 -> {
                    val buffer = codec.getOutputBuffer(index)!!
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && started) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buffer, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    fun finish(): Boolean {
        val index = dequeueInput()
        codec.queueInputBuffer(index, 0, 0, frame * 1_000_000L / fps, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(true)
        release()
        return started
    }

    fun abort() {
        try {
            release()
        } catch (_: Exception) {
        }
        File(path).delete()
    }

    private fun release() {
        try {
            codec.stop()
        } catch (_: Exception) {
        }
        codec.release()
        try {
            if (started) muxer.stop()
        } catch (_: Exception) {
        }
        muxer.release()
    }
}
