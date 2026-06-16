package com.moongate.mobile.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.moongate.mobile.domain.SecureCredentialReference
import com.moongate.mobile.domain.SecureCredentialStore
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class AndroidKeystoreCredentialStore(
    context: Context,
    private val keyAlias: String = KEY_ALIAS,
) : SecureCredentialStore {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    override suspend fun saveCredential(
        secret: String,
        reference: SecureCredentialReference,
    ): SecureCredentialReference {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val encrypted = cipher.doFinal(secret.toByteArray(Charsets.UTF_8))
        val encodedCiphertext = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        val encodedIv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)

        preferences.edit()
            .putString(ciphertextKey(reference), encodedCiphertext)
            .putString(ivKey(reference), encodedIv)
            .apply()

        return reference
    }

    override suspend fun deleteCredential(reference: SecureCredentialReference) {
        preferences.edit()
            .remove(ciphertextKey(reference))
            .remove(ivKey(reference))
            .apply()
    }

    override suspend fun hasCredential(reference: SecureCredentialReference): Boolean =
        preferences.contains(ciphertextKey(reference)) &&
            preferences.contains(ivKey(reference))

    override suspend fun credential(reference: SecureCredentialReference): String? {
        val encodedCiphertext = preferences.getString(ciphertextKey(reference), null)
            ?: return null
        val encodedIv = preferences.getString(ivKey(reference), null)
            ?: return null
        val ciphertext = Base64.decode(encodedCiphertext, Base64.NO_WRAP)
        val iv = Base64.decode(encodedIv, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(KEY_SIZE_BITS)
            .build()

        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun ciphertextKey(reference: SecureCredentialReference): String =
        "credential:${reference.storageHash}:ciphertext"

    private fun ivKey(reference: SecureCredentialReference): String =
        "credential:${reference.storageHash}:iv"

    private val SecureCredentialReference.storageHash: String
        get() {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest("${service}\u0000${account}".toByteArray(Charsets.UTF_8))
            return digest.joinToString(separator = "") { "%02x".format(it) }
        }

    private companion object {
        const val KEY_ALIAS = "moongate_mobile_translation_credentials_v1"
        const val PREFERENCES_NAME = "moongate_secure_credentials"
        const val GCM_TAG_BITS = 128
        const val KEY_SIZE_BITS = 256
    }
}
