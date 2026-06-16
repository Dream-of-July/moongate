package com.moongate.mobile.worker

import com.moongate.mobile.domain.MobileDownloadRequest
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.Locale
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

class AndroidDirectMediaBackgroundDownloader(
    private val downloadsDirectory: File,
    private val maxDownloadBytes: Long = 512L * 1024L * 1024L,
) : AndroidBackgroundDirectDownloader {
    override suspend fun download(
        request: MobileDownloadRequest,
        progress: suspend (AndroidBackgroundDownloadProgress) -> Unit,
    ): AndroidBackgroundDownloadedFile {
        if (!request.sourceURL.isSafeBackgroundSourceURL()) {
            throw AndroidBackgroundDownloadFailure.UnsupportedOnMobile(
                "Android background downloader requires a direct HTTPS media URL.",
            )
        }
        coroutineContext.ensureActive()
        if (!downloadsDirectory.exists() && !downloadsDirectory.mkdirs()) {
            throw AndroidBackgroundDownloadFailure.StorageFull(
                "Could not prepare Android background download storage.",
            )
        }
        val output = File(downloadsDirectory, request.backgroundDownloadFileName())
        val partialOutput = File(downloadsDirectory, "${output.name}.part")
        val replacementOutput = File(downloadsDirectory, "${output.name}.replace")
        val resumeOffset = existingPartialBytes(partialOutput)
        if (resumeOffset > maxDownloadBytes) {
            throw AndroidBackgroundDownloadFailure.StorageFull(
                "Android background download is too large.",
            )
        }
        val connection = (URI(request.sourceURL).toURL().openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            connectTimeout = 15_000
            readTimeout = 30_000
        }
        if (resumeOffset > 0L) {
            connection.setRequestProperty("Range", "bytes=$resumeOffset-")
        }
        var completed = false
        try {
            replacementOutput.delete()
            coroutineContext.ensureActive()
            val status = connection.responseCode
            coroutineContext.ensureActive()
            if (status !in 200..299) {
                throw AndroidBackgroundDownloadFailure.NetworkUnavailable(
                    "Android background download failed with HTTP $status",
                )
            }
            if (resumeOffset > 0L && status != HttpURLConnection.HTTP_PARTIAL && status != HttpURLConnection.HTTP_OK) {
                throw AndroidBackgroundDownloadFailure.NetworkUnavailable(
                    "Android background download resume failed with HTTP $status",
                )
            }
            if (status == HttpURLConnection.HTTP_OK && resumeOffset > 0L) {
                partialOutput.delete()
            }
            val shouldAppend = resumeOffset > 0L && status == HttpURLConnection.HTTP_PARTIAL
            val effectiveResumeOffset = if (shouldAppend) resumeOffset else 0L
            val finalURL = connection.url.toString()
            if (!finalURL.isSafeBackgroundSourceURL()) {
                throw AndroidBackgroundDownloadFailure.UnsupportedOnMobile(
                    "Android background download target changed to an unsupported URL.",
                )
            }
            val contentLength = connection.contentLengthLong
            val normalizedTotalBytes = contentLength
                .takeIf { it > 0L }
                ?.let { length -> if (shouldAppend) resumeOffset + length else length }
            if ((normalizedTotalBytes ?: contentLength) > maxDownloadBytes) {
                throw AndroidBackgroundDownloadFailure.StorageFull(
                    "Android background download is too large.",
                )
            }
            coroutineContext.ensureActive()
            connection.inputStream.use { input ->
                partialOutput.outputStream(append = shouldAppend).use { outputStream ->
                    val bytesCopied = input.copyBackgroundDownloadTo(
                        output = outputStream,
                        limitBytes = maxDownloadBytes - effectiveResumeOffset + 1L,
                        onBytesCopied = { copied ->
                            progress(
                                AndroidBackgroundDownloadProgress(
                                    bytesDownloaded = effectiveResumeOffset + copied,
                                    totalBytes = normalizedTotalBytes,
                                ),
                            )
                        },
                    )
                    if (effectiveResumeOffset + bytesCopied > maxDownloadBytes) {
                        throw AndroidBackgroundDownloadFailure.StorageFull(
                            "Android background download is too large.",
                        )
                    }
                }
            }
            coroutineContext.ensureActive()
            if (!partialOutput.renameTo(replacementOutput)) {
                throw AndroidBackgroundDownloadFailure.StorageFull(
                    "Could not stage Android background download.",
                )
            }
            coroutineContext.ensureActive()
            if (output.exists() && !output.delete()) {
                throw AndroidBackgroundDownloadFailure.StorageFull(
                    "Could not replace Android background download.",
                )
            }
            coroutineContext.ensureActive()
            if (!replacementOutput.renameTo(output)) {
                throw AndroidBackgroundDownloadFailure.StorageFull(
                    "Could not finalize Android background download.",
                )
            }
            completed = true
            return AndroidBackgroundDownloadedFile(
                storageIdentifier = "android-owned:${output.name}",
                byteCount = output.length(),
            )
        } finally {
            if (!completed) {
                replacementOutput.delete()
            }
            connection.disconnect()
        }
    }
}

private suspend fun InputStream.copyBackgroundDownloadTo(
    output: OutputStream,
    bufferSize: Int = DEFAULT_BUFFER_SIZE,
    limitBytes: Long,
    onBytesCopied: suspend (Long) -> Unit,
): Long {
    var bytesCopied = 0L
    val buffer = ByteArray(bufferSize)
    while (true) {
        coroutineContext.ensureActive()
        val bytesRead = read(buffer)
        coroutineContext.ensureActive()
        if (bytesRead < 0) {
            return bytesCopied
        }
        output.write(buffer, 0, bytesRead)
        bytesCopied += bytesRead.toLong()
        onBytesCopied(bytesCopied)
        coroutineContext.ensureActive()
        if (bytesCopied > limitBytes) {
            return bytesCopied
        }
    }
}

private fun existingPartialBytes(partialOutput: File): Long =
    partialOutput
        .takeIf { it.isFile }
        ?.length()
        ?.takeIf { it > 0L }
        ?: 0L

private fun MobileDownloadRequest.backgroundDownloadFileName(): String {
    val extension = URI(sourceURL).path
        .substringAfterLast('.', missingDelimiterValue = "mp4")
        .lowercase(Locale.US)
        .takeIf { it in setOf("mp4", "mov", "m4v", "webm") }
        ?: "mp4"
    val baseName = listOf(
        id.safeAndroidBackgroundFileNamePart(),
        (preferredTitle ?: videoID).safeAndroidBackgroundFileNamePart(),
    ).filter { it.isNotBlank() }
        .joinToString("-")
        .take(112)
        .ifBlank { "background-download" }
    return "$baseName.$extension"
}

private fun String.safeAndroidBackgroundFileNamePart(): String =
    map { character ->
        if (character.isLetterOrDigit() || character == '.' || character == '-' || character == '_') {
            character
        } else {
            '-'
        }
    }.joinToString("")
        .trim('-')
        .take(64)
