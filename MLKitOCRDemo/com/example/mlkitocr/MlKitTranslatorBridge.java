/*
 * Copyright (C) 2026 Antonio Alcázar Ruiz (MiTeruel) <mrgarciagarcia@gmail.com>
 * Part of the PluTony project. Licensed under the GNU GPL v3.0 or later;
 * see LICENSE for the full text.
 */

package com.example.mlkitocr;

import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.mlkit.common.model.DownloadConditions;
import com.google.mlkit.nl.translate.TranslateLanguage;
import com.google.mlkit.nl.translate.Translation;
import com.google.mlkit.nl.translate.Translator;
import com.google.mlkit.nl.translate.TranslatorOptions;

import java.util.List;
import java.util.Locale;

/**
 * Thin wrapper around ML Kit's on-device Translate API, meant to be called
 * from Delphi through JNI (see Android.JNI.MLKitTranslate.pas).
 *
 * Unlike MlKitTextRecognizerBridge (Play-Services-hosted), com.google.mlkit:translate
 * bundles its own TFLite inference engine directly in the app - only the
 * per-language model *data* is downloaded on demand via
 * translator.downloadModelIfNeeded(), which is what makes the first
 * translation for a given language pair slow (and require internet) while
 * later ones are instant/offline.
 *
 * NOTE: plain Java, not Kotlin - see MlKitTextRecognizerBridge.java for why.
 */
public class MlKitTranslatorBridge {

    private Translator translator;
    private String currentSourceLanguage;
    private String currentTargetLanguage;

    /**
     * Returns every language ML Kit Translate supports as
     * "code|DisplayName" pairs joined by ';' (e.g. "en|English;es|Spanish"),
     * so the Delphi side can populate two combo boxes without needing a
     * hand-maintained copy of ML Kit's language list.
     */
    public String getAllLanguages() {
        List<String> codes = TranslateLanguage.getAllLanguages();
        StringBuilder sb = new StringBuilder();
        for (String code : codes) {
            if (sb.length() > 0) {
                sb.append(';');
            }
            sb.append(code).append('|').append(displayNameFor(code));
        }
        return sb.toString();
    }

    private static String displayNameFor(String code) {
        String name = new Locale(code).getDisplayName(Locale.getDefault());
        if (name == null || name.isEmpty()) {
            return code;
        }
        return Character.toUpperCase(name.charAt(0)) + name.substring(1);
    }

    public void translate(final String sourceLanguage, final String targetLanguage,
                           final String text, final TranslateCallback callback) {
        if (text == null || text.trim().isEmpty()) {
            callback.onError("No hay texto para traducir");
            return;
        }
        try {
            ensureTranslator(sourceLanguage, targetLanguage);
            final Translator activeTranslator = translator;

            callback.onStatus("Comprobando modelo de idioma...");
            DownloadConditions conditions = new DownloadConditions.Builder().build();
            activeTranslator.downloadModelIfNeeded(conditions)
                    .addOnSuccessListener(new OnSuccessListener<Void>() {
                        @Override
                        public void onSuccess(Void unused) {
                            callback.onStatus("Traduciendo...");
                            activeTranslator.translate(text)
                                    .addOnSuccessListener(new OnSuccessListener<String>() {
                                        @Override
                                        public void onSuccess(String translatedText) {
                                            callback.onSuccess(translatedText);
                                        }
                                    })
                                    .addOnFailureListener(new OnFailureListener() {
                                        @Override
                                        public void onFailure(Exception e) {
                                            callback.onError(describe(e));
                                        }
                                    });
                        }
                    })
                    .addOnFailureListener(new OnFailureListener() {
                        @Override
                        public void onFailure(Exception e) {
                            callback.onError("Error descargando el modelo de idioma: " + describe(e));
                        }
                    });
        } catch (Exception e) {
            callback.onError(describe(e));
        }
    }

    private void ensureTranslator(String sourceLanguage, String targetLanguage) {
        if (translator != null
                && sourceLanguage.equals(currentSourceLanguage)
                && targetLanguage.equals(currentTargetLanguage)) {
            return;
        }
        if (translator != null) {
            translator.close();
        }
        TranslatorOptions options = new TranslatorOptions.Builder()
                .setSourceLanguage(sourceLanguage)
                .setTargetLanguage(targetLanguage)
                .build();
        translator = Translation.getClient(options);
        currentSourceLanguage = sourceLanguage;
        currentTargetLanguage = targetLanguage;
    }

    private static String describe(Exception e) {
        String message = e.getMessage();
        return (message != null && !message.isEmpty())
                ? message
                : e.getClass().getSimpleName();
    }
}
