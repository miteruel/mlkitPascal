/*
 * Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
 * Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
 * see LICENSE for the full text.
 */

package com.example.mlkitocr;

/**
 * Callback interface implemented on the Delphi side (as a JNI local object,
 * see Android.JNI.MLKitTranslate.pas / TTranslateCallbackImpl) to receive
 * progress and the result of an asynchronous translate request.
 */
public interface TranslateCallback {
    void onStatus(String message);
    void onSuccess(String translatedText);
    void onError(String message);
}
