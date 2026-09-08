/*
 * Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
 * Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
 * see LICENSE for the full text.
 */

package com.example.mlkitocr;

import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.mlkit.nl.languageid.LanguageIdentification;
import com.google.mlkit.nl.languageid.LanguageIdentifier;

/**
 * Thin wrapper around ML Kit's on-device Language Identification API, meant
 * to be called from Delphi through JNI (see Android.JNI.MLKitLanguageId.pas).
 *
 * Unlike Translate, this model ships bundled inside the AAR itself as a
 * small asset - there is nothing to download, identifyLanguage() works
 * offline from the very first call.
 *
 * NOTE: plain Java, not Kotlin - see MlKitTextRecognizerBridge.java for why.
 */
public class MlKitLanguageIdBridge {

    private final LanguageIdentifier identifier = LanguageIdentification.getClient();

    /**
     * Detects the dominant language of {@code text} and reports its BCP-47
     * code (e.g. "es", "en") back through {@code callback}. ML Kit reports
     * "und" when it cannot reliably determine the language (text too short,
     * mixed languages, etc.) - the Delphi side treats that as "not found".
     */
    public void identifyLanguage(final String text, final LanguageIdCallback callback) {
        if (text == null || text.trim().isEmpty()) {
            callback.onError("No hay texto para analizar");
            return;
        }
        try {
            identifier.identifyLanguage(text)
                    .addOnSuccessListener(new OnSuccessListener<String>() {
                        @Override
                        public void onSuccess(String languageCode) {
                            callback.onSuccess(languageCode);
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
