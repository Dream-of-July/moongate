package com.moongate.mobile.domain

private val SharedHttpUrlPattern = Regex(
    pattern = """https?://[^\s<>"']+""",
    option = RegexOption.IGNORE_CASE,
)

fun String.firstSharedHttpUrl(): String? {
    val candidate = SharedHttpUrlPattern.find(this)?.value
        ?.trimEnd('.', ',', ';', ':', ')', ']', '}', '>', '。', '，', '；', '、')
        ?: return null
    return candidate.takeIf {
        it.startsWith("http://", ignoreCase = true) ||
            it.startsWith("https://", ignoreCase = true)
    }
}
