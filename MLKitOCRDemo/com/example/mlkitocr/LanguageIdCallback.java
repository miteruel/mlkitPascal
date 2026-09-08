/*
 * Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
 * Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
 * see LICENSE for the full text.
 */

package com.example.mlkitocr;

/**
 * Callback interface implemented on the Delphi side (as a JNI local object,
 * see Android.JNI.MLKitLanguageId.pas) to receive the result of an
 * asynchronous language identification request.
 */
public interface LanguageIdCallback {
    void onSuccess(String languageCode);
    void onError(String message);
}
