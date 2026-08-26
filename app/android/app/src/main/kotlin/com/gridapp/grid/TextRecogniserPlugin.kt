package com.gridapp.grid

import android.graphics.BitmapFactory
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * On-device text recognition using ML Kit.
 *
 * ML Kit is the right engine on Android — it is bundled, accelerated and
 * accurate. It is only unusable on *iOS*, where its pods ship no arm64
 * simulator slice, which is why the two platforms use different engines
 * behind one Dart interface rather than sharing a Flutter package. See
 * ADR-0004.
 *
 * This class recognises text and nothing else. Choosing which digit run is
 * the meter register happens in Dart, in `DigitExtractor`, so that judgement
 * stays testable without a device and identical on both platforms.
 */
class TextRecogniserPlugin(
    private val context: android.content.Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "grid/text_recogniser"
    }

    private val recogniser by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(true)
            "recognise" -> recognise(call, result)
            else -> result.notImplemented()
        }
    }

    private fun recognise(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("bad_arguments", "recognise requires a 'path'", null)
            return
        }

        val file = File(path)
        if (!file.exists()) {
            result.error("unreadable_image", "No image at $path", null)
            return
        }

        // The image dimensions are needed to normalise bounding boxes, and
        // decoding bounds only is far cheaper than decoding the bitmap.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        val imageWidth = bounds.outWidth.toDouble()
        val imageHeight = bounds.outHeight.toDouble()
        if (imageWidth <= 0 || imageHeight <= 0) {
            result.error("unreadable_image", "Could not read the image size", null)
            return
        }

        val image = try {
            InputImage.fromFilePath(context, Uri.fromFile(file))
        } catch (e: Exception) {
            result.error("unreadable_image", e.message, null)
            return
        }

        recogniser.process(image)
            .addOnSuccessListener { text ->
                val blocks = mutableListOf<Map<String, Any>>()
                for (block in text.textBlocks) {
                    for (line in block.lines) {
                        val box = line.boundingBox ?: continue
                        blocks.add(
                            mapOf(
                                "text" to line.text,
                                // ML Kit reports confidence per element and
                                // not always at all. Where it is absent the
                                // extractor leans on geometry instead, which
                                // is why it must not be faked here.
                                "confidence" to (line.confidence?.toDouble() ?: 1.0),
                                // Normalise to 0..1 with a top-left origin,
                                // matching what Dart expects and what the iOS
                                // side produces after flipping its y axis.
                                "left" to (box.left / imageWidth),
                                "top" to (box.top / imageHeight),
                                "width" to (box.width() / imageWidth),
                                "height" to (box.height() / imageHeight),
                            )
                        )
                    }
                }
                result.success(blocks)
            }
            .addOnFailureListener {
                // Recognition failing is a normal outcome on a worn meter
                // face, not an error the user should see. Dart treats an
                // empty result as "fall back to manual entry".
                result.success(emptyList<Map<String, Any>>())
            }
    }
}
