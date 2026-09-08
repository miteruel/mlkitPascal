/*
 * Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
 * Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
 * see LICENSE for the full text.
 */

package com.example.mlkitocr;

import android.graphics.Bitmap;

import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

/**
 * Thin, synchronous-looking wrapper around ML Kit's Text Recognition v2 API,
 * meant to be called from Delphi through JNI (see Android.JNI.MLKitOCR.pas).
 *
 * One instance can be reused for multiple recognizeText() calls; the
 * underlying TextRecognizer is thread-safe and caches the detector model.
 *
 * NOTE: this class is plain Java (not Kotlin) on purpose: RAD Studio's
 * Android build pipeline compiles .java files added to the project with its
 * own javac invocation, but it has no Kotlin compiler integration. Writing
 * the wrapper in Kotlin would require an external build step producing a
 * .jar/.aar before RAD Studio could package it. Plain Java can be added to
 * the Delphi project as a source file directly.
 */
public class MlKitTextRecognizerBridge {

    private final TextRecognizer recognizer =
            TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);

    public void recognizeText(final Bitmap bitmap, final OcrCallback callback) {
        if (bitmap == null) {
            callback.onError("Bitmap is null");
            return;
        }
        try {
            InputImage image = InputImage.fromBitmap(bitmap, 0);
            recognizer.process(image)
                    .addOnSuccessListener(new OnSuccessListener<Text>() {
                        @Override
                        public void onSuccess(Text result) {
                            callback.onSuccess(result.getText());
                        }
                    })
                    .addOnFailureListener(new OnFailureListener() {
                        @Override
                        public void onFailure(Exception e) {
                            callback.onError(describe(e));
                        }
                    });
        } catch (Exception e) {
            callback.onError(describe(e));
        }
    }

    private static String describe(Exception e) {
        String message = e.getMessage();
        return (message != null && !message.isEmpty())
                ? message
                : e.getClass().getSimpleName();
    }
}
