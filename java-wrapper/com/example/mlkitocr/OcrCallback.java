/*
 * Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
 * Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
 * see LICENSE for the full text.
 */

package com.example.mlkitocr;

/**
 * Callback interface implemented on the Delphi side (as a JNI local object,
 * see Android.JNI.MLKitOCR.pas / TOcrCallbackImpl) to receive the result of
 * an asynchronous text-recognition request.
 */
public interface OcrCallback {
    void onSuccess(String text);
    void onError(String message);
}
