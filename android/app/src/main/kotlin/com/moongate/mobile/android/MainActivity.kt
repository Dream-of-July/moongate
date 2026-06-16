package com.moongate.mobile.android

import android.Manifest
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.progressSemantics
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Api
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.LibraryBooks
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.moongate.mobile.data.repository.AndroidTaskRecoveryPolicy
import com.moongate.mobile.data.repository.JsonTaskRepository
import com.moongate.mobile.domain.AndroidAppState
import com.moongate.mobile.domain.AndroidActionState
import com.moongate.mobile.domain.AndroidActionAvailability
import com.moongate.mobile.domain.AndroidAddExportMode
import com.moongate.mobile.domain.AndroidBackgroundTaskStatus
import com.moongate.mobile.domain.AndroidDownloadItem
import com.moongate.mobile.domain.AndroidDownloadState
import com.moongate.mobile.domain.AndroidImportedFile
import com.moongate.mobile.domain.AndroidLibraryAction
import com.moongate.mobile.domain.AndroidLibraryItem
import com.moongate.mobile.domain.AndroidLibraryRecoveryAction
import com.moongate.mobile.domain.AndroidLibraryRecoveryPresentation
import com.moongate.mobile.domain.AndroidLocalTranslationModel
import com.moongate.mobile.domain.AndroidModelDownloadState
import com.moongate.mobile.domain.AndroidNotificationPermissionState
import com.moongate.mobile.domain.AndroidQueueAction
import com.moongate.mobile.domain.AndroidQueueRecoveryAction
import com.moongate.mobile.domain.AndroidQueueRecoveryPresentation
import com.moongate.mobile.domain.AndroidSurface
import com.moongate.mobile.domain.AndroidAddReadyState
import com.moongate.mobile.domain.MobileAddSessionState
import com.moongate.mobile.domain.MobileDownloadRequest
import com.moongate.mobile.domain.MobileFormatChoice
import com.moongate.mobile.domain.MobileSubtitleChoice
import com.moongate.mobile.domain.MobileTaskSnapshot
import com.moongate.mobile.domain.MobileUnsupportedReason
import com.moongate.mobile.domain.MobileVideoCandidate
import com.moongate.mobile.domain.SecureCredentialReference
import com.moongate.mobile.domain.SecureCredentialStore
import com.moongate.mobile.domain.TaskRepository
import com.moongate.mobile.domain.appOwnedDownloadFileName
import com.moongate.mobile.domain.firstSharedHttpUrl
import com.moongate.mobile.domain.label
import com.moongate.mobile.domain.restorableAfterCancellation
import com.moongate.mobile.worker.AndroidBackgroundObservedWorkState
import com.moongate.mobile.worker.AndroidBackgroundObservedWorkStatus
import com.moongate.mobile.worker.AndroidBackgroundWorkCoordinator
import com.moongate.mobile.worker.AndroidBackgroundWorkHandoff
import com.moongate.mobile.worker.AndroidBackgroundWorkStatusProjection
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val AndroidSubtitleMimeTypes = arrayOf(
    "text/*",
    "application/x-subrip",
    "application/octet-stream",
)

class MainActivity : ComponentActivity() {
    private var sharedURL by mutableStateOf<String?>(null)
    private var foregroundRefreshRequest by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sharedURL = intent.sharedHttpUrl()

        setContent {
            MoongateApp(
                initialSharedURL = sharedURL,
                onSharedURLConsumed = { sharedURL = null },
                foregroundRefreshRequest = foregroundRefreshRequest,
            )
        }
    }

    override fun onResume() {
        super.onResume()
        foregroundRefreshRequest += 1
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedURL = intent.sharedHttpUrl()
    }
}

private sealed interface TaskPersistenceRequest {
    data class Save(val snapshot: MobileTaskSnapshot) : TaskPersistenceRequest
    data class Remove(val id: String) : TaskPersistenceRequest
}

@Composable
fun MoongateApp(
    appState: AndroidAppState = AndroidAppState.live(),
    initialSharedURL: String? = null,
    onSharedURLConsumed: () -> Unit = {},
    foregroundRefreshRequest: Int = 0,
) {
    val context = LocalContext.current
    val credentialStore = remember { AndroidKeystoreCredentialStore(context) }
    val taskRepository = remember { context.androidTaskRepository() }
    val backgroundWorkCoordinator = remember { AndroidBackgroundWorkCoordinator.from(context) }
    val taskPersistenceRequests = remember { Channel<TaskPersistenceRequest>(Channel.UNLIMITED) }
    var currentAppState by remember { mutableStateOf(appState) }
    val coroutineScope = rememberCoroutineScope()

    fun persistQueueItem(id: String) {
        val snapshot = currentAppState.persistedTaskForQueueItem(id) ?: return
        taskPersistenceRequests.trySend(TaskPersistenceRequest.Save(snapshot))
    }

    fun removePersistedTask(id: String) {
        taskPersistenceRequests.trySend(TaskPersistenceRequest.Remove(id))
    }

    suspend fun savePersistedTask(snapshot: MobileTaskSnapshot) {
        taskRepository.saveTask(snapshot)
    }

    suspend fun removePersistedTaskFromRepository(id: String) {
        taskRepository.removeTask(id)
    }

    suspend fun refreshPersistedTasks() {
        val restoredTasks = withContext(Dispatchers.IO) {
            AndroidTaskRecoveryPolicy.recoverAll(taskRepository.loadTasks())
        }
        currentAppState = currentAppState.withPersistedTasks(restoredTasks)
        if (restoredTasks.isNotEmpty()) {
            restoredTasks.forEach { task ->
                taskPersistenceRequests.trySend(TaskPersistenceRequest.Save(task))
            }
        }
    }

    fun applyObservedBackgroundStatus(
        taskID: String,
        observed: AndroidBackgroundObservedWorkStatus,
    ) {
        if (observed.state == AndroidBackgroundObservedWorkState.SUCCEEDED) {
            coroutineScope.launch {
                refreshPersistedTasks()
            }
            return
        }
        val snapshot = currentAppState.persistedTaskForQueueItem(taskID) ?: return
        val projected = AndroidBackgroundWorkStatusProjection.apply(snapshot, observed)
        if (projected == snapshot) {
            return
        }
        currentAppState = currentAppState.withProjectedBackgroundTask(projected)
        taskPersistenceRequests.trySend(TaskPersistenceRequest.Save(projected))
    }

    LaunchedEffect(credentialStore) {
        val reference = AndroidTranslationCredentialReference
        val hasStoredCredential = runCatching {
            credentialStore.hasCredential(reference)
        }.getOrDefault(false)
        if (hasStoredCredential && currentAppState.settings.apiKeyReference == null) {
            currentAppState = currentAppState.withAPIKeyReference(reference)
        }
    }

    LaunchedEffect(context) {
        currentAppState = currentAppState.withAndroidNotificationPermission(
            context.androidNotificationPermissionState(),
        )
    }

    LaunchedEffect(foregroundRefreshRequest, taskRepository) {
        refreshPersistedTasks()
    }

    val observedBackgroundTaskIDs = currentAppState.queue
        .filterNot { item ->
            item.state == AndroidDownloadState.COMPLETED ||
                item.state == AndroidDownloadState.FAILED
        }
        .map { item -> item.id }
        .distinct()
        .sorted()
    val observedBackgroundStatusHandler by rememberUpdatedState(
        newValue = { taskID: String, status: AndroidBackgroundObservedWorkStatus ->
            coroutineScope.launch {
                applyObservedBackgroundStatus(taskID, status)
            }
        },
    )
    DisposableEffect(backgroundWorkCoordinator, observedBackgroundTaskIDs) {
        val registration = backgroundWorkCoordinator.observeForegroundWorkStatuses(
            taskIDs = observedBackgroundTaskIDs,
            onStatus = { taskID, status ->
                observedBackgroundStatusHandler(taskID, status)
            },
        )
        onDispose {
            registration.cancel()
        }
    }

    LaunchedEffect(taskPersistenceRequests, taskRepository) {
        withContext(Dispatchers.IO) {
            for (request in taskPersistenceRequests) {
                when (request) {
                    is TaskPersistenceRequest.Save -> savePersistedTask(request.snapshot)
                    is TaskPersistenceRequest.Remove -> removePersistedTaskFromRepository(request.id)
                }
            }
        }
    }

    LaunchedEffect(initialSharedURL) {
        val sharedURL = initialSharedURL ?: return@LaunchedEffect
        currentAppState = currentAppState.withStagedDirectUrl(sharedURL)
        onSharedURLConsumed()
    }

    MaterialTheme {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            MoongateShell(
                appState = currentAppState,
                credentialStore = credentialStore,
                backgroundWorkCoordinator = backgroundWorkCoordinator,
                onDirectUrlStaged = { url ->
                    currentAppState = currentAppState.withStagedDirectUrl(url)
                },
                onCandidateSelected = { candidateID ->
                    currentAppState = currentAppState.withSelectedAddCandidate(candidateID)
                },
                onDownloadRequestQueued = { request ->
                    currentAppState = currentAppState.withQueuedDownloadRequest(request)
                    persistQueueItem(currentAppState.queue.last().id)
                },
                onQueueItemRemoved = { item ->
                    currentAppState = currentAppState.withoutQueueItem(item.id)
                    removePersistedTask(item.id)
                },
                onQueueItemRestored = { item ->
                    currentAppState = currentAppState.withQueuedDownloadItem(item)
                    persistQueueItem(item.id)
                },
                onDirectDownloadStarted = { item ->
                    currentAppState = currentAppState.withDownloadStarted(item)
                    persistQueueItem(item.id)
                },
                onDirectDownloadProgress = { item, bytesDownloaded, totalBytes ->
                    currentAppState = currentAppState.withDownloadProgress(item, bytesDownloaded, totalBytes)
                    persistQueueItem(item.id)
                },
                onDirectDownloadCompleted = { item, storageUri, byteCount ->
                    currentAppState = currentAppState.withDownloadedFile(item, storageUri, byteCount)
                    persistQueueItem(item.id)
                },
                onDirectDownloadFailed = { item, message ->
                    currentAppState = currentAppState.withDownloadFailed(item, message)
                    persistQueueItem(item.id)
                },
                onImportedFile = { importedFile ->
                    currentAppState = currentAppState.withImportedFile(importedFile)
                    persistQueueItem(currentAppState.queue.last().id)
                },
                onImportedSubtitle = { importedSubtitle ->
                    currentAppState = currentAppState.withImportedSubtitle(importedSubtitle)
                },
                onLibraryItemDeleted = { item ->
                    currentAppState = currentAppState.withoutLibraryItem(item.id)
                    removePersistedTask(item.id.removePrefix("library-"))
                },
                onLibraryItemRestored = { item ->
                    currentAppState = currentAppState.withRestoredLibraryItem(item)
                    persistQueueItem(item.id.removePrefix("library-"))
                },
                onLibraryFileRecovered = { item, importedFile ->
                    currentAppState = currentAppState.withRecoveredLibraryFile(item, importedFile)
                    persistQueueItem(item.id.removePrefix("library-"))
                },
                onAPIKeyReferenceChanged = { reference ->
                    currentAppState = currentAppState.withAPIKeyReference(reference)
                },
                onAPIKeyReferenceCleared = {
                    currentAppState = currentAppState.withoutAPIKeyReference()
                },
                onNotificationPermissionChanged = { state ->
                    currentAppState = currentAppState.withAndroidNotificationPermission(state)
                },
                onTranslatedSubtitleExportRequested = { item ->
                    currentAppState = currentAppState.withTranslatedSubtitleExportStarted(item)
                    persistQueueItem(item.id)
                },
                onRenderExportRequested = { item ->
                    currentAppState = currentAppState.withRenderExportStarted(item)
                    persistQueueItem(item.id)
                },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MoongateShell(
    appState: AndroidAppState,
    credentialStore: SecureCredentialStore,
    backgroundWorkCoordinator: AndroidBackgroundWorkCoordinator,
    onDirectUrlStaged: (String) -> Unit,
    onCandidateSelected: (String) -> Unit,
    onDownloadRequestQueued: (MobileDownloadRequest) -> Unit,
    onQueueItemRemoved: (AndroidDownloadItem) -> Unit,
    onDirectDownloadStarted: (AndroidDownloadItem) -> Unit,
    onDirectDownloadProgress: (AndroidDownloadItem, Long, Long?) -> Unit,
    onDirectDownloadCompleted: (AndroidDownloadItem, String, Long?) -> Unit,
    onDirectDownloadFailed: (AndroidDownloadItem, String) -> Unit,
    onImportedFile: (AndroidImportedFile) -> Unit,
    onImportedSubtitle: (AndroidImportedFile) -> Unit,
    onLibraryItemDeleted: (AndroidLibraryItem) -> Unit,
    onQueueItemRestored: (AndroidDownloadItem) -> Unit,
    onLibraryItemRestored: (AndroidLibraryItem) -> Unit,
    onLibraryFileRecovered: (AndroidLibraryItem, AndroidImportedFile) -> Unit,
    onAPIKeyReferenceChanged: (SecureCredentialReference) -> Unit,
    onAPIKeyReferenceCleared: () -> Unit,
    onNotificationPermissionChanged: (AndroidNotificationPermissionState) -> Unit,
    onTranslatedSubtitleExportRequested: (AndroidDownloadItem) -> Unit,
    onRenderExportRequested: (AndroidDownloadItem) -> Unit,
) {
    val context = LocalContext.current
    var selectedSurface by rememberSaveable { mutableStateOf(appState.selectedSurface) }
    val navigationItems = appState.surfaces.map { it.toNavigationItem() }
    val coroutineScope = rememberCoroutineScope()
    val foregroundDownloader = remember { AndroidForegroundDirectDownloader(context) }
    val downloadJobs = remember { mutableStateMapOf<String, Job>() }
    val snackbarHostState = remember { SnackbarHostState() }
    var pendingSaveCopyItem by remember { mutableStateOf<AndroidLibraryItem?>(null) }
    var pendingQueueDeletion by remember { mutableStateOf<AndroidDownloadItem?>(null) }
    var pendingLibraryDeletion by remember { mutableStateOf<AndroidLibraryItem?>(null) }
    var pendingLibraryDeletionAction by remember { mutableStateOf<AndroidActionState?>(null) }
    var pendingLibraryFileRecovery by remember { mutableStateOf<AndroidLibraryItem?>(null) }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        onNotificationPermissionChanged(
            if (granted) {
                AndroidNotificationPermissionState.GRANTED
            } else {
                AndroidNotificationPermissionState.DENIED
            },
        )
    }
    val showLibraryFeedback: (String) -> Unit = { message ->
        coroutineScope.launch {
            snackbarHostState.showSnackbar(message)
        }
    }
    val deleteLibraryItemAfterConfirmation = onLibraryItemDeleted
    val confirmQueueDeletion: (AndroidDownloadItem) -> Unit = { item ->
        confirmQueueDeletion(
            item = item,
            downloadJobs = downloadJobs,
            backgroundWorkCoordinator = backgroundWorkCoordinator,
            onQueueItemRemoved = onQueueItemRemoved,
            onRestore = onQueueItemRestored,
            snackbarHostState = snackbarHostState,
            coroutineScope = coroutineScope,
        )
    }
    val confirmLibraryDeletion: (AndroidLibraryItem, AndroidActionState) -> Unit = { item, action ->
        confirmLibraryDeletion(
            context = context,
            item = item,
            action = action,
            onDelete = deleteLibraryItemAfterConfirmation,
            onRestore = onLibraryItemRestored,
            snackbarHostState = snackbarHostState,
            coroutineScope = coroutineScope,
            onFeedback = showLibraryFeedback,
        )
    }
    val startQueueItemDownload: (AndroidDownloadItem) -> Unit = startDownload@ { item ->
        if (item.isActive && item.primaryAction.isEnabled) {
            pendingQueueDeletion = item
            return@startDownload
        }
        if (item.state == AndroidDownloadState.COMPLETED) {
            val completedLibraryItem = appState.library.firstOrNull { it.id == "library-${item.id}" }
            selectedSurface = if (completedLibraryItem != null) {
                AndroidSurface.LIBRARY
            } else {
                AndroidSurface.QUEUE
            }
            return@startDownload
        }
        if (!item.isReadyForForegroundDownload()) {
            selectedSurface = AndroidSurface.LIBRARY
            return@startDownload
        }
        when (backgroundWorkCoordinator.enqueueDownloadIfReady(item)) {
            is AndroidBackgroundWorkHandoff.Enqueued -> {
                selectedSurface = AndroidSurface.QUEUE
                return@startDownload
            }
            is AndroidBackgroundWorkHandoff.Blocked -> Unit
        }
        downloadJobs[item.id]?.cancel()
        val downloadJob = coroutineScope.launch {
            onDirectDownloadStarted(item)
            runCatching {
                foregroundDownloader.download(item) { progress ->
                    withContext(Dispatchers.Main) {
                        onDirectDownloadProgress(item, progress.bytesDownloaded, progress.totalBytes)
                    }
                }
            }.onSuccess { downloaded ->
                downloadJobs.remove(item.id)
                onDirectDownloadCompleted(item, downloaded.storageUri, downloaded.byteCount)
                selectedSurface = AndroidSurface.LIBRARY
            }.onFailure { error ->
                downloadJobs.remove(item.id)
                if (error is CancellationException) {
                    throw error
                }
                val failureMessage = "下载没有完成，请检查网络后重试。"
                onDirectDownloadFailed(item, failureMessage)
                snackbarHostState.showSnackbar(failureMessage)
                selectedSurface = AndroidSurface.QUEUE
            }
        }
        downloadJobs[item.id] = downloadJob
    }
    val fileImportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        val persistableFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        val takeFlags = persistableFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        runCatching {
            context.contentResolver.takePersistableUriPermission(uri, takeFlags)
        }
        val importedFile = AndroidImportedFile(
            id = uri.androidImportID(),
            displayName = uri.displayName(context),
            mimeType = context.contentResolver.getType(uri),
            byteCount = uri.byteCount(context),
            contentUri = uri.toString(),
        )
        val recoveryItem = pendingLibraryFileRecovery
        pendingLibraryFileRecovery = null
        if (recoveryItem != null) {
            onLibraryFileRecovered(recoveryItem, importedFile)
            selectedSurface = AndroidSurface.LIBRARY
        } else {
            onImportedFile(importedFile)
            selectedSurface = AndroidSurface.QUEUE
        }
    }
    val subtitleImportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        val persistableFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        val takeFlags = persistableFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        runCatching {
            context.contentResolver.takePersistableUriPermission(uri, takeFlags)
        }
        val importedSubtitle = AndroidImportedFile(
            id = uri.androidImportID(),
            displayName = uri.displayName(context),
            mimeType = context.contentResolver.getType(uri),
            byteCount = uri.byteCount(context),
            contentUri = uri.toString(),
        )
        onImportedSubtitle(importedSubtitle)
        selectedSurface = AndroidSurface.ADD
    }
    val saveCopyLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("*/*"),
    ) { destination ->
        val item = pendingSaveCopyItem
        pendingSaveCopyItem = null
        if (item == null || destination == null) {
            return@rememberLauncherForActivityResult
        }
        val source = context.exportableLibraryUri(item)
        if (source == null) {
            showLibraryFeedback(LibraryFileUnavailableMessage)
            return@rememberLauncherForActivityResult
        }
        runCatching {
            context.copyLibraryItemBytes(source, destination)
        }.onSuccess {
            showLibraryFeedback(LibraryCopySavedMessage)
        }.onFailure {
            showLibraryFeedback(LibraryCopyFailedMessage)
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(text = "视频下载器")
                        Text(
                            text = selectedSurface.title,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
        bottomBar = {
            NavigationBar {
                navigationItems.forEach { item ->
                    NavigationBarItem(
                        selected = selectedSurface == item.surface,
                        onClick = { selectedSurface = item.surface },
                        icon = {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = null,
                            )
                        },
                        label = { Text(item.label) },
                    )
                }
            }
        },
    ) { innerPadding ->
        when (selectedSurface) {
            AndroidSurface.ADD -> AddScreen(
                appState = appState,
                onAddUrlClick = { url ->
                    onDirectUrlStaged(url)
                    selectedSurface = AndroidSurface.ADD
                },
                onCandidateSelected = onCandidateSelected,
                onImportClick = {
                    pendingLibraryFileRecovery = null
                    fileImportLauncher.launch(arrayOf("video/*"))
                },
                onSubtitleImportClick = { subtitleImportLauncher.launch(AndroidSubtitleMimeTypes) },
                onEnqueueClick = { request ->
                    onDownloadRequestQueued(request)
                    selectedSurface = AndroidSurface.QUEUE
                },
                modifier = Modifier
                    .padding(innerPadding)
                    .fillMaxSize(),
            )

            AndroidSurface.QUEUE -> QueueScreen(
                items = appState.queue,
                onAddClick = { selectedSurface = AndroidSurface.ADD },
                onPrimaryActionClick = startQueueItemDownload,
                onRecoveryActionClick = { item, recoveryAction ->
                    handleQueueRecoveryAction(
                        item = item,
                        recoveryAction = recoveryAction,
                        onRetryDownload = startQueueItemDownload,
                        onRestartInForeground = { selectedSurface = AndroidSurface.QUEUE },
                        onReopenAdd = { selectedSurface = AndroidSurface.ADD },
                        onReselectFile = {
                            pendingLibraryFileRecovery = null
                            fileImportLauncher.launch(arrayOf("video/*"))
                        },
                        onOpenSettings = { selectedSurface = AndroidSurface.SETTINGS },
                    )
                },
                onSecondaryActionClick = { item, action ->
                    handleQueueAction(
                        item = item,
                        action = action,
                        onRemove = { pendingQueueDeletion = item },
                        onExportTranslatedSubtitle = onTranslatedSubtitleExportRequested,
                        onExportRenderedVideo = onRenderExportRequested,
                    )
                },
                modifier = Modifier
                    .padding(innerPadding)
                    .fillMaxSize(),
            )

            AndroidSurface.LIBRARY -> LibraryScreen(
                items = appState.library,
                onAddClick = { selectedSurface = AndroidSurface.ADD },
                onPrimaryActionClick = { item ->
                    val action = item.primaryAction
                    if (action.isDestructiveLibraryAction()) {
                        pendingLibraryDeletion = item
                        pendingLibraryDeletionAction = action
                        return@LibraryScreen
                    }
                    handleLibraryAction(
                        context,
                        item,
                        action,
                        onDelete = { deleteItem ->
                            pendingLibraryDeletion = deleteItem
                            pendingLibraryDeletionAction = action
                        },
                        onSaveCopy = { saveItem ->
                            pendingSaveCopyItem = saveItem
                            saveCopyLauncher.launch(saveItem.suggestedCopyFileName)
                        },
                        onFeedback = showLibraryFeedback,
                    )
                },
                onRecoveryActionClick = { item, recoveryAction ->
                    handleLibraryRecoveryAction(
                        item = item,
                        recoveryAction = recoveryAction,
                        onReselectFile = { recoveryItem ->
                            pendingLibraryFileRecovery = recoveryItem
                            fileImportLauncher.launch(arrayOf("video/*"))
                        },
                    )
                },
                onSecondaryActionClick = { item, action ->
                    if (action.isDestructiveLibraryAction()) {
                        pendingLibraryDeletion = item
                        pendingLibraryDeletionAction = action
                        return@LibraryScreen
                    }
                    handleLibraryAction(
                        context,
                        item,
                        action,
                        onDelete = { deleteItem ->
                            pendingLibraryDeletion = deleteItem
                            pendingLibraryDeletionAction = action
                        },
                        onSaveCopy = { saveItem ->
                            pendingSaveCopyItem = saveItem
                            saveCopyLauncher.launch(saveItem.suggestedCopyFileName)
                        },
                        onFeedback = showLibraryFeedback,
                    )
                },
                modifier = Modifier
                    .padding(innerPadding)
                    .fillMaxSize(),
            )

            AndroidSurface.SETTINGS -> SettingsScreen(
                appState = appState,
                credentialStore = credentialStore,
                onAPIKeyReferenceChanged = onAPIKeyReferenceChanged,
                onAPIKeyReferenceCleared = onAPIKeyReferenceCleared,
                onNotificationPermissionClick = {
                    val permissionState = appState.settings.backgroundRuntimeReadiness.notificationPermission
                    if (permissionState == AndroidNotificationPermissionState.DENIED) {
                        context.openAppNotificationSettings()
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else {
                        onNotificationPermissionChanged(AndroidNotificationPermissionState.NOT_REQUIRED)
                    }
                },
                modifier = Modifier
                    .padding(innerPadding)
                    .fillMaxSize(),
            )
        }
    }

    pendingQueueDeletion?.let { item ->
        ConfirmDestructiveActionDialog(
            title = "移除任务？",
            body = "移除后会从队列和资料库中删除这条记录。",
            confirmLabel = "移除",
            onDismiss = { pendingQueueDeletion = null },
            onConfirm = {
                pendingQueueDeletion = null
                confirmQueueDeletion(item)
            },
        )
    }

    pendingLibraryDeletion?.let { item ->
        ConfirmDestructiveActionDialog(
            title = libraryDeletionTitle(pendingLibraryDeletionAction),
            body = libraryDeletionBody(pendingLibraryDeletionAction),
            confirmLabel = pendingLibraryDeletionAction?.label ?: "删除",
            onDismiss = {
                pendingLibraryDeletion = null
                pendingLibraryDeletionAction = null
            },
            onConfirm = {
                val action = pendingLibraryDeletionAction ?: item.secondaryActions
                    .firstOrNull { it.libraryAction == AndroidLibraryAction.DELETE_RECORD }
                    ?: item.primaryAction
                pendingLibraryDeletion = null
                pendingLibraryDeletionAction = null
                confirmLibraryDeletion(item, action)
            },
        )
    }
}

@Composable
private fun ConfirmDestructiveActionDialog(
    title: String,
    body: String,
    confirmLabel: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(body) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirmLabel)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消")
            }
        },
    )
}

@Composable
private fun AddScreen(
    appState: AndroidAppState,
    onAddUrlClick: ((String) -> Unit)? = null,
    onCandidateSelected: ((String) -> Unit)? = null,
    onImportClick: (() -> Unit)? = null,
    onSubtitleImportClick: (() -> Unit)? = null,
    onEnqueueClick: ((MobileDownloadRequest) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    var url by remember { mutableStateOf("") }
    val readyState = appState.addReadyState
    var selectedFormatID by rememberSaveable(readyState?.sessionID) {
        mutableStateOf(readyState?.selectedFormatID)
    }
    var selectedManualSubtitleIDs by rememberSaveable(
        readyState?.sessionID,
        readyState?.selectedManualSubtitleIDs,
    ) {
        mutableStateOf(readyState?.selectedManualSubtitleIDs.orEmpty())
    }
    var selectedAutoSubtitleIDs by rememberSaveable(
        readyState?.sessionID,
        readyState?.selectedAutoSubtitleIDs,
    ) {
        mutableStateOf(readyState?.selectedAutoSubtitleIDs.orEmpty())
    }
    var selectedExportMode by rememberSaveable(
        readyState?.sessionID,
        readyState?.selectedExportMode,
    ) {
        mutableStateOf(readyState?.selectedExportMode ?: AndroidAddExportMode.SUBTITLE_FILE)
    }
    val currentReadyState = readyState?.copy(
        selectedFormatID = selectedFormatID,
        selectedManualSubtitleIDs = selectedManualSubtitleIDs,
        selectedAutoSubtitleIDs = selectedAutoSubtitleIDs,
        selectedExportMode = selectedExportMode,
    )

    LazyColumn(
        modifier = modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            SectionCard(title = appState.fileImportState.title) {
                Text(
                    text = appState.fileImportState.primaryAction.helperText
                        ?: appState.fileImportState.helperText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(8.dp))
                PrimaryActionButton(
                    action = appState.fileImportState.primaryAction,
                    icon = Icons.Outlined.Folder,
                    enabled = appState.fileImportState.primaryAction.isEnabled,
                    onClick = { onImportClick?.invoke() },
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = appState.fileImportState.primaryAction.statusLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        item {
            SectionCard(title = appState.addUrlState.title) {
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("视频 URL") },
                    placeholder = { Text("https://example.com/video.mp4") },
                    singleLine = true,
                    isError = appState.addUrlState.errorMessage != null,
                    supportingText = {
                        Text(
                            appState.addUrlState.errorMessage
                                ?: appState.addUrlState.primaryAction.helperText
                                ?: appState.addUrlState.helperText,
                        )
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Link,
                            contentDescription = null,
                        )
                    },
                )
                Spacer(modifier = Modifier.height(8.dp))
                PrimaryActionButton(
                    action = appState.addUrlState.primaryAction,
                    icon = Icons.Outlined.Add,
                    enabled = url.isNotBlank() && appState.addUrlState.primaryAction.isEnabled,
                    onClick = { onAddUrlClick?.invoke(url) },
                )
                if (!appState.addUrlState.primaryAction.isEnabled) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = appState.addUrlState.primaryAction.statusLabel,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        item {
            AndroidAddSessionStateCard(
                sessionState = appState.addSessionState,
                candidates = appState.addCandidates,
                selectedCandidateID = appState.selectedAddCandidateID,
                errorMessage = appState.addUrlState.errorMessage,
                hasReadyState = currentReadyState != null,
                onCandidateSelected = onCandidateSelected,
            )
        }

        currentReadyState?.let { ready ->
            item {
                ReadyVideoCard(readyState = ready)
            }

            item {
                FormatSelectionCard(
                    readyState = ready,
                    onFormatSelected = { selectedFormatID = it },
                )
            }

            item {
                SectionCard(title = "本地字幕") {
                    Text(
                        text = "导入 SRT、VTT 或纯文本字幕后会加入手动字幕选择。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = { onSubtitleImportClick?.invoke() },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Translate,
                            contentDescription = null,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("导入字幕")
                    }
                }
            }

            item {
                SubtitleSelectionCard(
                    title = "手动字幕",
                    options = ready.manualSubtitles,
                    selectedSubtitleIDs = selectedManualSubtitleIDs,
                    emptyText = "不使用手动字幕",
                    onSubtitleToggled = { subtitleID ->
                        selectedManualSubtitleIDs = selectedManualSubtitleIDs.toggled(subtitleID)
                    },
                )
            }

            item {
                SubtitleSelectionCard(
                    title = "自动字幕",
                    options = ready.autoSubtitles,
                    selectedSubtitleIDs = selectedAutoSubtitleIDs,
                    emptyText = "不使用自动字幕",
                    onSubtitleToggled = { subtitleID ->
                        selectedAutoSubtitleIDs = selectedAutoSubtitleIDs.toggled(subtitleID)
                    },
                )
            }

            item {
                ExportModeSelectionCard(
                    title = "导出方式",
                    selectedExportMode = selectedExportMode,
                    onExportModeSelected = { selectedExportMode = it },
                )
            }

            item {
                SectionCard(title = "加入队列") {
                    Text(
                        text = "${ready.formatLabel} · ${ready.manualSubtitleLabel} · ${ready.autoSubtitleLabel} · ${ready.exportModeLabel}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Button(
                        onClick = { onEnqueueClick?.invoke(ready.downloadRequest) },
                        enabled = ready.canCreateDownloadRequest,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Download,
                            contentDescription = null,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(ready.enqueueAction.label)
                    }
                }
            }
        }

        if (appState.mockBoundaries.isNotEmpty()) {
            item {
                MockBoundaries(boundaries = appState.mockBoundaries)
            }
        }
    }
}

@Composable
private fun AndroidAddSessionStateCard(
    sessionState: MobileAddSessionState,
    candidates: List<MobileVideoCandidate>,
    selectedCandidateID: String?,
    errorMessage: String?,
    hasReadyState: Boolean,
    onCandidateSelected: ((String) -> Unit)?,
) {
    when (sessionState) {
        MobileAddSessionState.IDLE -> Unit
        MobileAddSessionState.ANALYZING -> AddStateCard(
            title = "正在检查链接",
            body = "正在确认链接是否为手机端可处理的直接媒体文件。",
        )
        MobileAddSessionState.CANDIDATE_SELECTION -> AddStateCard(
            title = "选择视频",
            body = "发现多个可用候选项时，会先让你确认要下载的视频。",
        )
        MobileAddSessionState.READY -> if (!hasReadyState) {
            AddStateCard(
                title = "需要重新检查",
                body = "当前没有可加入队列的媒体信息，请重新检查链接或导入视频。",
            )
        } else {
            Unit
        }
        MobileAddSessionState.UNSUPPORTED -> AddStateCard(
            title = "当前链接暂不支持",
            body = errorMessage ?: "手机端目前只支持 HTTPS 直接媒体文件链接；网页链接请先在桌面端解析。",
            isError = true,
        )
        MobileAddSessionState.FAILED -> AddStateCard(
            title = "检查失败",
            body = errorMessage ?: "请确认这是 HTTPS 直接媒体文件链接后重试。",
            isError = true,
        )
    }
    if (sessionState == MobileAddSessionState.CANDIDATE_SELECTION && candidates.isNotEmpty()) {
        Spacer(modifier = Modifier.height(12.dp))
        AndroidCandidateSelectionCard(
            candidates = candidates,
            selectedCandidateID = selectedCandidateID,
            onCandidateSelected = onCandidateSelected,
        )
    }
}

@Composable
private fun AndroidCandidateSelectionCard(
    candidates: List<MobileVideoCandidate>,
    selectedCandidateID: String?,
    onCandidateSelected: ((String) -> Unit)?,
) {
    SectionCard(title = "候选视频") {
        candidates.forEach { candidate ->
            AndroidCandidateRow(
                candidate = candidate,
                isSelected = selectedCandidateID == candidate.id,
                onCandidateSelected = onCandidateSelected,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
private fun AndroidCandidateRow(
    candidate: MobileVideoCandidate,
    isSelected: Boolean,
    onCandidateSelected: ((String) -> Unit)?,
) {
    val isSupported = candidate.isSupportedOnMobile
    val reasonLabel = candidateUnsupportedReasonLabel(candidate.unsupportedReason)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small,
        color = if (isSelected) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surface
        },
        contentColor = if (isSelected) {
            MaterialTheme.colorScheme.onPrimaryContainer
        } else {
            MaterialTheme.colorScheme.onSurface
        },
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = candidate.title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            candidate.detail?.let { detail ->
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = detail,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (reasonLabel != null) {
                    StatusPill(text = reasonLabel)
                } else {
                    StatusPill(text = if (isSelected) "已选择" else "可继续")
                }
                if (isSupported) {
                    Button(
                        enabled = onCandidateSelected != null,
                        onClick = { onCandidateSelected?.invoke(candidate.id) },
                    ) {
                        Text(if (isSelected) "已选择" else "选择")
                    }
                }
            }
        }
    }
}

private fun candidateUnsupportedReasonLabel(reason: MobileUnsupportedReason?): String? =
    when (reason) {
        MobileUnsupportedReason.REQUIRES_DESKTOP_EXTRACTOR -> "需要桌面端"
        MobileUnsupportedReason.DRM_OR_ACCESS_CONTROL -> "受限内容"
        MobileUnsupportedReason.LOGIN_REQUIRED -> "需要登录"
        MobileUnsupportedReason.UNSUPPORTED_FORMAT -> "格式不支持"
        MobileUnsupportedReason.UNKNOWN -> "暂不支持"
        null -> null
    }
}

@Composable
private fun AddStateCard(
    title: String,
    body: String,
    isError: Boolean = false,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        color = if (isError) {
            MaterialTheme.colorScheme.errorContainer
        } else {
            MaterialTheme.colorScheme.secondaryContainer
        },
        contentColor = if (isError) {
            MaterialTheme.colorScheme.onErrorContainer
        } else {
            MaterialTheme.colorScheme.onSecondaryContainer
        },
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(text = body, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun QueueScreen(
    items: List<AndroidDownloadItem>,
    onAddClick: () -> Unit,
    onPrimaryActionClick: ((AndroidDownloadItem) -> Unit)?,
    onRecoveryActionClick: (AndroidDownloadItem, AndroidQueueRecoveryAction) -> Unit,
    onSecondaryActionClick: (AndroidDownloadItem, AndroidActionState) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) {
        EmptyState(
            title = "队列为空",
            body = "添加链接或导入文件后，任务会出现在这里。",
            actionLabel = "去添加",
            onActionClick = onAddClick,
            modifier = modifier.padding(16.dp),
        )
        return
    }

    LazyColumn(
        modifier = modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(items, key = { it.id }) { item ->
            QueueItemCard(
                item = item,
                onPrimaryActionClick = onPrimaryActionClick,
                onRecoveryActionClick = onRecoveryActionClick,
                onSecondaryActionClick = onSecondaryActionClick,
            )
        }
    }
}

@Composable
private fun LibraryScreen(
    items: List<AndroidLibraryItem>,
    onAddClick: () -> Unit,
    onPrimaryActionClick: ((AndroidLibraryItem) -> Unit)?,
    onRecoveryActionClick: (AndroidLibraryItem, AndroidLibraryRecoveryAction) -> Unit,
    onSecondaryActionClick: (AndroidLibraryItem, AndroidActionState) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) {
        EmptyState(
            title = "资料库为空",
            body = "完成的视频和字幕会列在这里。",
            actionLabel = "去添加",
            onActionClick = onAddClick,
            modifier = modifier.padding(16.dp),
        )
        return
    }

    LazyColumn(
        modifier = modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(items, key = { it.id }) { item ->
            LibraryItemCard(
                item = item,
                onPrimaryActionClick = onPrimaryActionClick,
                onRecoveryActionClick = onRecoveryActionClick,
                onSecondaryActionClick = onSecondaryActionClick,
            )
        }
    }
}

@Composable
private fun SettingsScreen(
    appState: AndroidAppState,
    credentialStore: SecureCredentialStore,
    onAPIKeyReferenceChanged: (SecureCredentialReference) -> Unit,
    onAPIKeyReferenceCleared: () -> Unit,
    onNotificationPermissionClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val model = appState.settings.localModel
    val cloudReadiness = appState.settings.cloudTranslationReadiness
    var apiKeyDraft by remember { mutableStateOf("") }
    var apiKeySaveStatus by remember { mutableStateOf<String?>(null) }
    val coroutineScope = rememberCoroutineScope()

    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SectionCard(title = "API key") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = appState.settings.apiKeyStatusText,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = appState.settings.apiKeyAction.helperText
                            ?: appState.settings.apiKeyMockMessage,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Icon(
                    imageVector = Icons.Outlined.Api,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = apiKeyDraft,
                onValueChange = { apiKeyDraft = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("API key") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                supportingText = {
                    Text(apiKeySaveStatus ?: "仅用于本次保存；保存后输入框会清空。")
                },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Outlined.Api,
                        contentDescription = null,
                    )
                },
            )
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedButton(
                onClick = {
                    val secret = apiKeyDraft.trim()
                    val reference = AndroidTranslationCredentialReference
                    coroutineScope.launch {
                        runCatching {
                            credentialStore.saveCredential(secret, reference)
                        }.onSuccess { savedReference ->
                            apiKeyDraft = ""
                            apiKeySaveStatus = "已保存。"
                            onAPIKeyReferenceChanged(savedReference)
                        }.onFailure {
                            apiKeySaveStatus = "保存失败，请重试。"
                        }
                    }
                },
                enabled = apiKeyDraft.trim().isNotEmpty(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Api,
                    contentDescription = null,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(appState.settings.apiKeyAction.label)
            }
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(
                onClick = {
                    val reference = appState.settings.apiKeyReference
                        ?: return@OutlinedButton
                    coroutineScope.launch {
                        runCatching {
                            credentialStore.deleteCredential(reference)
                        }.onSuccess {
                            apiKeyDraft = ""
                            apiKeySaveStatus = "已移除。"
                            onAPIKeyReferenceCleared()
                        }.onFailure {
                            apiKeySaveStatus = "移除失败，请重试。"
                        }
                    }
                },
                enabled = appState.settings.hasConfiguredAPIKey,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Delete,
                    contentDescription = null,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("移除 API key")
            }
            Spacer(modifier = Modifier.height(8.dp))
            ActionStatusChip(appState.settings.apiKeyAction)
        }

        SectionCard(title = "云端翻译") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = cloudReadiness.protocol.label,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = appState.settings.cloudTranslationDetailText,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                StatusPill(text = appState.settings.cloudTranslationStatusText)
            }
            if (cloudReadiness.readinessIssues.size > 1) {
                Spacer(modifier = Modifier.height(8.dp))
                cloudReadiness.readinessIssues.forEach { issue ->
                    Text(
                        text = "- $issue",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            ActionStatusChip(appState.settings.cloudTranslationAction)
        }

        SectionCard(title = "本机翻译") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = model.displayName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = model.readinessIssues.firstOrNull()
                            ?: "本机翻译可用前，请先使用云端 API 翻译。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                StatusPill(text = localModelStatusLabel(model))
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Outlined.Translate,
                    contentDescription = "本机翻译状态",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
            if (model.downloadState == AndroidModelDownloadState.QUEUED ||
                model.downloadState == AndroidModelDownloadState.DOWNLOADING
            ) {
                Spacer(modifier = Modifier.height(12.dp))
                LinearProgressIndicator(
                    progress = { model.downloadFraction ?: 0f },
                    modifier = Modifier
                        .fillMaxWidth()
                        .progressSemantics(model.downloadFraction ?: 0f)
                        .semantics { stateDescription = localModelProgressDescription(model) },
                )
            }
        }

        SectionCard(title = "后台处理") {
            val permissionAction = appState.settings.notificationPermissionAction
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "通知权限",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = permissionAction.helperText ?: "后台任务必须先有系统可见通知。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                StatusPill(text = permissionAction.statusLabel)
            }
            Spacer(modifier = Modifier.height(8.dp))
            PrimaryActionButton(
                action = permissionAction,
                icon = Icons.Outlined.Settings,
                enabled = permissionAction.availability != AndroidActionAvailability.SYSTEM_BLOCKED,
                onClick = onNotificationPermissionClick,
            )
            Spacer(modifier = Modifier.height(12.dp))
            appState.settings.backgroundCapabilities.forEach { capability ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Top,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = capability.title,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = capability.detail,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    StatusPill(text = capability.statusLabel)
                }
                Spacer(modifier = Modifier.height(10.dp))
            }
        }
    }
}

@Composable
private fun QueueItemCard(
    item: AndroidDownloadItem,
    onPrimaryActionClick: ((AndroidDownloadItem) -> Unit)?,
    onRecoveryActionClick: (AndroidDownloadItem, AndroidQueueRecoveryAction) -> Unit,
    onSecondaryActionClick: (AndroidDownloadItem, AndroidActionState) -> Unit,
) {
    SectionCard(title = item.title) {
        Text(
            text = "${item.sourceLabel} · ${item.state.label}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(12.dp))
        item.progressPercent?.let { progress ->
            LinearProgressIndicator(
                progress = { progress / 100f },
                modifier = Modifier
                    .fillMaxWidth()
                    .progressSemantics(progress / 100f)
                    .semantics { stateDescription = queueProgressDescription(progress) },
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "$progress%",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
        Text(text = item.detail, style = MaterialTheme.typography.bodyMedium)
        item.recoveryPresentation?.let { recovery ->
            Spacer(modifier = Modifier.height(8.dp))
            RecoveryMessage(
                recovery = recovery,
                onActionClick = { action -> onRecoveryActionClick(item, action) },
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = item.selectionSummary,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StatusPill(text = item.backgroundStatus.label)
            if (onPrimaryActionClick != null && item.primaryAction.isEnabled) {
                PrimaryActionButton(
                    action = item.primaryAction,
                    icon = item.primaryAction.icon,
                    enabled = true,
                    onClick = { onPrimaryActionClick(item) },
                    compact = true,
                )
            } else {
                ActionStatusChip(action = item.primaryAction)
            }
        }
        if (item.secondaryActions.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            SecondaryActionRow(
                actions = item.secondaryActions,
                onActionClick = { action -> onSecondaryActionClick(item, action) },
            )
        }
    }
}

@Composable
private fun RecoveryMessage(
    recovery: AndroidQueueRecoveryPresentation,
    onActionClick: (AndroidQueueRecoveryAction) -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = recovery.title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = recovery.nextStep,
                style = MaterialTheme.typography.bodyMedium,
            )
            recovery.actionLabel?.let { label ->
                Spacer(modifier = Modifier.height(8.dp))
                TextButton(
                    enabled = recovery.action != null,
                    onClick = { recovery.action?.let(onActionClick) },
                ) {
                    Text(label)
                }
            }
        }
    }
}

@Composable
private fun LibraryRecoveryMessage(
    recovery: AndroidLibraryRecoveryPresentation,
    onActionClick: (AndroidLibraryRecoveryAction) -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = recovery.title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = recovery.nextStep,
                style = MaterialTheme.typography.bodyMedium,
            )
            recovery.actionLabel?.let { label ->
                Spacer(modifier = Modifier.height(8.dp))
                TextButton(
                    enabled = recovery.action != null,
                    onClick = { recovery.action?.let(onActionClick) },
                ) {
                    Text(label)
                }
            }
        }
    }
}

@Composable
private fun LibraryItemCard(
    item: AndroidLibraryItem,
    onPrimaryActionClick: ((AndroidLibraryItem) -> Unit)?,
    onRecoveryActionClick: (AndroidLibraryItem, AndroidLibraryRecoveryAction) -> Unit,
    onSecondaryActionClick: (AndroidLibraryItem, AndroidActionState) -> Unit,
) {
    SectionCard(title = item.title) {
        Text(
            text = "${item.createdAtLabel} · ${item.availability.label}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(12.dp))
        item.artifacts.forEach { artifact ->
            Text(
                text = "${artifact.kind.label}: ${artifact.displayName}",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        item.recoveryPresentation?.let { recovery ->
            Spacer(modifier = Modifier.height(8.dp))
            LibraryRecoveryMessage(
                recovery = recovery,
                onActionClick = { action -> onRecoveryActionClick(item, action) },
            )
        }
        Spacer(modifier = Modifier.height(12.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StatusPill(text = item.primaryAction.statusLabel)
            if (onPrimaryActionClick != null && item.primaryAction.isEnabled) {
                PrimaryActionButton(
                    action = item.primaryAction,
                    icon = item.primaryAction.icon,
                    enabled = true,
                    onClick = { onPrimaryActionClick(item) },
                    compact = true,
                )
            } else {
                ActionStatusChip(action = item.primaryAction)
            }
        }
        if (item.secondaryActions.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            SecondaryActionRow(
                actions = item.secondaryActions,
                onActionClick = { action -> onSecondaryActionClick(item, action) },
            )
        }
    }
}

@Composable
private fun ReadyVideoCard(readyState: AndroidAddReadyState) {
    SectionCard(title = readyState.videoInfo.title) {
        readyState.videoInfo.durationSeconds?.let { duration ->
            Text(
                text = duration.durationLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
        Text(
            text = "选择保存格式和字幕后加入队列。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun FormatSelectionCard(
    readyState: AndroidAddReadyState,
    onFormatSelected: (String) -> Unit,
) {
    SectionCard(title = "保存格式") {
        Text(
            text = readyState.formatLabel,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(10.dp))
        readyState.videoInfo.formats.forEach { format ->
            FormatChoiceChip(
                format = format,
                selected = readyState.selectedFormat?.id == format.id,
                onFormatSelected = onFormatSelected,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun FormatChoiceChip(
    format: MobileFormatChoice,
    selected: Boolean,
    onFormatSelected: (String) -> Unit,
) {
    FilterChip(
        selected = selected,
        onClick = { onFormatSelected(format.id) },
        label = {
            Text(
                text = format.detail?.let { "${format.label} · $it" } ?: format.label,
            )
        },
    )
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun SubtitleSelectionCard(
    title: String,
    options: List<MobileSubtitleChoice>,
    selectedSubtitleIDs: List<String>,
    emptyText: String,
    onSubtitleToggled: (String) -> Unit,
) {
    SectionCard(title = title) {
        if (options.isEmpty()) {
            Text(
                text = emptyText,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            return@SectionCard
        }

        options.forEach { subtitle ->
            FilterChip(
                selected = selectedSubtitleIDs.contains(subtitle.id),
                onClick = { onSubtitleToggled(subtitle.id) },
                label = { Text(subtitle.label) },
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun ExportModeSelectionCard(
    title: String,
    selectedExportMode: AndroidAddExportMode,
    onExportModeSelected: (AndroidAddExportMode) -> Unit,
) {
    SectionCard(title = title) {
        AndroidAddExportMode.values().forEach { mode ->
            FilterChip(
                selected = selectedExportMode == mode,
                onClick = { onExportModeSelected(mode) },
                label = {
                    Text("${mode.label} · ${mode.detail}")
                },
            )
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
private fun SectionCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(8.dp))
            content()
        }
    }
}

@Composable
private fun MockBanner(
    title: String,
    body: String,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.secondaryContainer,
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(text = body, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun MockBoundaries(boundaries: List<String>) {
    SectionCard(title = "未实现边界") {
        boundaries.forEach { boundary ->
            Text(
                text = boundary,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun EmptyState(
    title: String,
    body: String,
    actionLabel: String? = null,
    onActionClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        actionLabel?.let { label ->
            Spacer(modifier = Modifier.height(16.dp))
            Button(onClick = { onActionClick?.invoke() }) {
                Icon(
                    imageVector = Icons.Outlined.Add,
                    contentDescription = null,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(label)
            }
        }
    }
}

@Composable
private fun StatusPill(text: String) {
    Surface(
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.primaryContainer,
        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
private fun ActionStatusChip(action: AndroidActionState) {
    StatusPill(text = action.statusLabel)
}

@Composable
private fun PrimaryActionButton(
    action: AndroidActionState,
    icon: ImageVector,
    enabled: Boolean,
    onClick: (() -> Unit)?,
    compact: Boolean = false,
) {
    val isEnabled = enabled && action.isEnabled && onClick != null
    val modifier = if (compact) Modifier else Modifier.fillMaxWidth()
    Button(
        onClick = { onClick?.invoke() },
        enabled = isEnabled,
        modifier = modifier,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(action.label)
    }
}

@Composable
private fun SecondaryActionRow(
    actions: List<AndroidActionState>,
    onActionClick: (AndroidActionState) -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        actions.forEach { action ->
            OutlinedButton(
                onClick = { onActionClick(action) },
                enabled = action.isEnabled,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(action.label)
            }
        }
    }
}

private fun libraryDeletionTitle(action: AndroidActionState?): String =
    when (action?.libraryAction) {
        AndroidLibraryAction.DELETE_FILE -> "删除文件？"
        AndroidLibraryAction.DELETE_RECORD -> "删除记录？"
        else -> "删除？"
    }

private fun libraryDeletionBody(action: AndroidActionState?): String =
    when (action?.libraryAction) {
        AndroidLibraryAction.DELETE_FILE -> "删除后会先从资料库移除，撤销窗口结束后再删除 App 内文件。"
        AndroidLibraryAction.DELETE_RECORD -> "删除后只会移除资料库记录，不会删除原文件。"
        else -> "删除前请确认这项操作。"
    }

private data class NavigationItem(
    val surface: AndroidSurface,
    val label: String,
    val icon: ImageVector,
)

private fun AndroidSurface.toNavigationItem(): NavigationItem =
    when (this) {
        AndroidSurface.ADD -> NavigationItem(this, "添加", Icons.Outlined.Add)
        AndroidSurface.QUEUE -> NavigationItem(this, "队列", Icons.Outlined.Download)
        AndroidSurface.LIBRARY -> NavigationItem(this, "资料库", Icons.Outlined.LibraryBooks)
        AndroidSurface.SETTINGS -> NavigationItem(this, "设置", Icons.Outlined.Settings)
    }

private val AndroidSurface.title: String
    get() = when (this) {
        AndroidSurface.ADD -> "添加"
        AndroidSurface.QUEUE -> "队列"
        AndroidSurface.LIBRARY -> "资料库"
        AndroidSurface.SETTINGS -> "设置"
    }

private val com.moongate.mobile.domain.AndroidDownloadState.label: String
    get() = when (this) {
        com.moongate.mobile.domain.AndroidDownloadState.QUEUED -> "排队中"
        com.moongate.mobile.domain.AndroidDownloadState.DOWNLOADING -> "下载中"
        com.moongate.mobile.domain.AndroidDownloadState.TRANSLATING -> "翻译中"
        com.moongate.mobile.domain.AndroidDownloadState.WAITING_FOR_FOREGROUND -> "需要回到前台"
        com.moongate.mobile.domain.AndroidDownloadState.COMPLETED -> "已完成"
        com.moongate.mobile.domain.AndroidDownloadState.FAILED -> "失败"
    }

private val AndroidBackgroundTaskStatus.label: String
    get() = when (this) {
        AndroidBackgroundTaskStatus.FOREGROUND_ONLY -> "保持前台"
        AndroidBackgroundTaskStatus.TRANSFER_ALLOWED -> "可后台继续"
        AndroidBackgroundTaskStatus.SYSTEM_DEFERRED -> "系统稍后"
        AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER -> "回到应用"
    }

private val com.moongate.mobile.domain.AndroidLibraryAvailability.label: String
    get() = when (this) {
        com.moongate.mobile.domain.AndroidLibraryAvailability.MOCK_ONLY -> "需要文件位置"
        com.moongate.mobile.domain.AndroidLibraryAvailability.AVAILABLE -> "可用"
        com.moongate.mobile.domain.AndroidLibraryAvailability.FILE_MISSING -> "文件缺失"
        com.moongate.mobile.domain.AndroidLibraryAvailability.PERMISSION_DENIED -> "无权限"
    }

private val com.moongate.mobile.domain.AndroidLibraryArtifactKind.label: String
    get() = when (this) {
        com.moongate.mobile.domain.AndroidLibraryArtifactKind.ORIGINAL_VIDEO -> "原视频"
        com.moongate.mobile.domain.AndroidLibraryArtifactKind.TRANSLATED_SUBTITLE -> "翻译字幕"
        com.moongate.mobile.domain.AndroidLibraryArtifactKind.RENDERED_VIDEO -> "渲染视频"
    }

private val AndroidActionState.icon: ImageVector
    get() = when (availability) {
        AndroidActionAvailability.ENABLED -> Icons.Outlined.Folder
        AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER -> Icons.Outlined.Download
        AndroidActionAvailability.NEEDS_CONFIGURATION -> Icons.Outlined.Settings
        AndroidActionAvailability.SYSTEM_BLOCKED -> Icons.Outlined.Download
    }

private val AndroidLocalTranslationModel.downloadFraction: Float?
    get() {
        val total = totalBytes ?: return null
        if (total <= 0L) return null
        return (downloadedBytes.toFloat() / total.toFloat()).coerceIn(0f, 1f)
    }

private fun localModelProgressDescription(model: AndroidLocalTranslationModel): String {
    val percentage = model.downloadFraction?.let { "${(it * 100).toInt()}%" }
    return when (model.downloadState) {
        AndroidModelDownloadState.QUEUED -> percentage?.let { "模型下载排队中，$it" } ?: "模型下载排队中"
        AndroidModelDownloadState.DOWNLOADING -> percentage?.let { "模型下载中，$it" } ?: "模型下载中"
        AndroidModelDownloadState.NOT_DOWNLOADED -> "模型未下载"
        AndroidModelDownloadState.READY -> "模型可用"
        AndroidModelDownloadState.FAILED -> "模型下载失败"
    }
}

private fun localModelStatusLabel(model: AndroidLocalTranslationModel): String =
    if (model.downloadState == AndroidModelDownloadState.NOT_DOWNLOADED && model.readinessIssues.isNotEmpty()) {
        "当前不可用"
    } else {
        model.statusLabel
    }

private fun queueProgressDescription(progress: Int): String =
    "任务进度 ${progress.coerceIn(0, 100)}%"

private val Double.durationLabel: String
    get() {
        val totalSeconds = toInt()
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "%d:%02d".format(minutes, seconds)
    }

private fun List<String>.toggled(value: String): List<String> =
    if (contains(value)) {
        filterNot { it == value }
    } else {
        this + value
    }

@Preview(showBackground = true)
@Composable
private fun MoongateAppPreview() {
    MaterialTheme {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            MoongateShell(
                appState = AndroidAppState.sample(),
                credentialStore = PreviewCredentialStore,
                backgroundWorkCoordinator = PreviewBackgroundWorkCoordinator,
                onDirectUrlStaged = ::ignoreDirectUrl,
                onCandidateSelected = ::ignoreCandidateSelection,
                onDownloadRequestQueued = ::ignoreDownloadRequest,
                onQueueItemRemoved = ::ignoreQueuePrimaryAction,
                onQueueItemRestored = ::ignoreQueuePrimaryAction,
                onDirectDownloadStarted = ::ignoreQueuePrimaryAction,
                onDirectDownloadProgress = ::ignoreDirectDownloadProgress,
                onDirectDownloadCompleted = ::ignoreDirectDownloadCompleted,
                onDirectDownloadFailed = ::ignoreDirectDownloadFailed,
                onImportedFile = ::ignoreImportedFile,
                onImportedSubtitle = ::ignoreImportedFile,
                onLibraryItemDeleted = ::ignoreLibraryPrimaryAction,
                onLibraryItemRestored = ::ignoreLibraryPrimaryAction,
                onLibraryFileRecovered = ::ignoreLibraryFileRecovered,
                onAPIKeyReferenceChanged = ::ignoreCredentialReference,
                onAPIKeyReferenceCleared = ::ignoreUnitAction,
                onNotificationPermissionChanged = ::ignoreNotificationPermission,
                onTranslatedSubtitleExportRequested = ::ignoreQueuePrimaryAction,
                onRenderExportRequested = ::ignoreQueuePrimaryAction,
            )
        }
    }
}

private fun ignoreDirectUrl(url: String) = Unit

private fun ignoreCandidateSelection(candidateID: String) = Unit

private fun ignoreDownloadRequest(request: MobileDownloadRequest) = Unit

private fun ignoreImportedFile(file: AndroidImportedFile) = Unit

private fun ignoreQueuePrimaryAction(item: AndroidDownloadItem) = Unit

private fun ignoreDirectDownloadProgress(
    item: AndroidDownloadItem,
    bytesDownloaded: Long,
    totalBytes: Long?,
) = Unit

private fun ignoreDirectDownloadCompleted(
    item: AndroidDownloadItem,
    storageUri: String,
    byteCount: Long?,
) = Unit

private fun ignoreDirectDownloadFailed(item: AndroidDownloadItem, message: String) = Unit

private fun ignoreLibraryPrimaryAction(item: AndroidLibraryItem) = Unit

private fun ignoreLibraryFileRecovered(item: AndroidLibraryItem, file: AndroidImportedFile) = Unit

private fun ignoreCredentialReference(reference: SecureCredentialReference) = Unit

private fun ignoreUnitAction() = Unit

private fun ignoreNotificationPermission(state: AndroidNotificationPermissionState) = Unit

private data class AndroidDownloadedFile(
    val storageUri: String,
    val byteCount: Long?,
)

private class AndroidForegroundDirectDownloader(
    private val context: Context,
    private val maxDownloadBytes: Long = 512L * 1024L * 1024L,
) {
    data class AndroidDownloadProgress(
        val bytesDownloaded: Long,
        val totalBytes: Long?,
    )

    suspend fun download(
        item: AndroidDownloadItem,
        onProgress: suspend (AndroidDownloadProgress) -> Unit,
    ): AndroidDownloadedFile =
        withContext(Dispatchers.IO) {
            val sourceUrl = item.sourceUrlForDownload
            if (sourceUrl.isBlank()) {
                throw IllegalArgumentException("Missing source URL")
            }
            val url = URL(sourceUrl)
            if (!url.isSafeForegroundDirectMediaUrl()) {
                throw IllegalArgumentException("Only HTTPS direct media downloads are supported.")
            }

            val downloadsDirectory = File(context.filesDir, "downloads")
            downloadsDirectory.mkdirs()
            val fileName = item.downloadFileName()
            val partialOutput = File(downloadsDirectory, "$fileName.part")
            val replacementOutput = File(downloadsDirectory, "$fileName.replace")
            val output = File(downloadsDirectory, fileName)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            var completed = false
            try {
                partialOutput.delete()
                replacementOutput.delete()
                if (connection.responseCode !in 200..299) {
                    throw IOException("Download failed with HTTP ${connection.responseCode}")
                }
                val finalUrl = connection.url
                if (!finalUrl.isSafeForegroundDirectMediaUrl()) {
                    throw IOException("Download target changed to an unsupported mobile URL.")
                }
                val contentLength = connection.contentLengthLong
                if (contentLength > maxDownloadBytes) {
                    throw IOException("Download is too large for foreground mobile storage")
                }
                val normalizedContentLength = contentLength.takeIf { it > 0L }

                connection.inputStream.use { input ->
                    partialOutput.outputStream().use { outputStream ->
                        val bytesCopied = input.copyTo(
                            outputStream,
                            limitBytes = maxDownloadBytes + 1,
                            onBytesCopied = { bytesCopied ->
                                onProgress(AndroidDownloadProgress(bytesCopied, normalizedContentLength))
                            },
                        )
                        if (bytesCopied > maxDownloadBytes) {
                            throw IOException("Download is too large for foreground mobile storage")
                        }
                    }
                }
                if (!partialOutput.renameTo(replacementOutput)) {
                    throw IOException("Could not finalize downloaded file")
                }
                if (output.exists() && !output.delete()) {
                    throw IOException("Could not replace downloaded file")
                }
                if (!replacementOutput.renameTo(output)) {
                    throw IOException("Could not finalize downloaded file")
                }
                completed = true
                val fileName = output.name
                AndroidDownloadedFile(
                    storageUri = "android-owned:$fileName",
                    byteCount = output.length(),
                )
            } finally {
                if (!completed) {
                    partialOutput.delete()
                    replacementOutput.delete()
                }
                connection.disconnect()
            }
        }
}

private fun URL.isSafeForegroundDirectMediaUrl(): Boolean {
    if (protocol != "https") return false
    if (!userInfo.isNullOrBlank()) return false
    if (query != null || ref != null) return false
    return path.substringAfterLast('.', missingDelimiterValue = "")
        .lowercase()
        .let { it in setOf("mp4", "mov", "m4v", "webm") }
}

private suspend fun InputStream.copyTo(
    output: OutputStream,
    bufferSize: Int = DEFAULT_BUFFER_SIZE,
    limitBytes: Long,
    onBytesCopied: suspend (Long) -> Unit = {},
): Long {
    var bytesCopied = 0L
    val buffer = ByteArray(bufferSize)
    while (true) {
        val bytesRead = read(buffer)
        if (bytesRead < 0) {
            return bytesCopied
        }
        output.write(buffer, 0, bytesRead)
        bytesCopied += bytesRead.toLong()
        onBytesCopied(bytesCopied)
        if (bytesCopied > limitBytes) {
            return bytesCopied
        }
    }
}

private fun AndroidDownloadItem.downloadFileName(): String {
    return appOwnedDownloadFileName()
}

private fun handleQueueRecoveryAction(
    item: AndroidDownloadItem,
    recoveryAction: AndroidQueueRecoveryAction,
    onRetryDownload: (AndroidDownloadItem) -> Unit,
    onRestartInForeground: () -> Unit,
    onReopenAdd: () -> Unit,
    onReselectFile: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    when (recoveryAction) {
        AndroidQueueRecoveryAction.RETRY_DOWNLOAD -> onRetryDownload(item)
        AndroidQueueRecoveryAction.RESTART_IN_FOREGROUND -> onRestartInForeground()
        AndroidQueueRecoveryAction.REOPEN_ADD -> onReopenAdd()
        AndroidQueueRecoveryAction.RESELECT_FILE -> onReselectFile()
        AndroidQueueRecoveryAction.OPEN_SETTINGS -> onOpenSettings()
    }
}

private fun handleQueueAction(
    item: AndroidDownloadItem,
    action: AndroidActionState,
    onRemove: (AndroidDownloadItem) -> Unit,
    onExportTranslatedSubtitle: (AndroidDownloadItem) -> Unit,
    onExportRenderedVideo: (AndroidDownloadItem) -> Unit,
) {
    if (!action.isEnabled) {
        return
    }
    when (action.queueAction) {
        AndroidQueueAction.REMOVE -> onRemove(item)
        AndroidQueueAction.EXPORT_TRANSLATED_SUBTITLE -> onExportTranslatedSubtitle(item)
        AndroidQueueAction.EXPORT_RENDERED_VIDEO -> onExportRenderedVideo(item)
        null -> Unit
    }
}

private fun handleLibraryRecoveryAction(
    item: AndroidLibraryItem,
    recoveryAction: AndroidLibraryRecoveryAction,
    onReselectFile: (AndroidLibraryItem) -> Unit,
) {
    when (recoveryAction) {
        AndroidLibraryRecoveryAction.RESELECT_FILE -> onReselectFile(item)
    }
}

private fun handleLibraryAction(
    context: Context,
    item: AndroidLibraryItem,
    action: AndroidActionState,
    onDelete: (AndroidLibraryItem) -> Unit,
    onSaveCopy: (AndroidLibraryItem) -> Unit,
    onFeedback: (String) -> Unit,
) {
    if (!action.isEnabled) {
        return
    }
    when (action.libraryAction) {
        AndroidLibraryAction.OPEN -> context.openLibraryItem(item, onFeedback)
        AndroidLibraryAction.SHARE -> context.shareLibraryItem(item, onFeedback)
        AndroidLibraryAction.SAVE_COPY -> context.saveLibraryItemCopy(item, onSaveCopy, onFeedback)
        AndroidLibraryAction.DELETE_FILE -> onDelete(item)
        AndroidLibraryAction.DELETE_RECORD -> onDelete(item)
        null -> Unit
    }
}

private fun AndroidActionState.isDestructiveLibraryAction(): Boolean {
    return libraryAction == AndroidLibraryAction.DELETE_FILE ||
        libraryAction == AndroidLibraryAction.DELETE_RECORD
}

private fun confirmQueueDeletion(
    item: AndroidDownloadItem,
    downloadJobs: MutableMap<String, Job>,
    backgroundWorkCoordinator: AndroidBackgroundWorkCoordinator,
    onQueueItemRemoved: (AndroidDownloadItem) -> Unit,
    onRestore: (AndroidDownloadItem) -> Unit,
    snackbarHostState: SnackbarHostState,
    coroutineScope: kotlinx.coroutines.CoroutineScope,
) {
    downloadJobs.remove(item.id)?.cancel()
    backgroundWorkCoordinator.cancelDownload(item.id)
    onQueueItemRemoved(item)
    coroutineScope.launch {
        val result = snackbarHostState.showSnackbar(
            message = "已移除 ${item.title}",
            actionLabel = "撤销",
        )
        if (result == SnackbarResult.ActionPerformed) {
            onRestore(item.restorableAfterCancellation())
        }
    }
}

private fun confirmLibraryDeletion(
    context: Context,
    item: AndroidLibraryItem,
    action: AndroidActionState,
    onDelete: (AndroidLibraryItem) -> Unit,
    onRestore: (AndroidLibraryItem) -> Unit,
    snackbarHostState: SnackbarHostState,
    coroutineScope: kotlinx.coroutines.CoroutineScope,
    onFeedback: (String) -> Unit,
) {
    if (!action.isEnabled) {
        return
    }
    val shouldDeleteFileAfterUndoWindow = when (action.libraryAction) {
        AndroidLibraryAction.DELETE_FILE -> true
        AndroidLibraryAction.DELETE_RECORD -> false
        else -> return
    }
    if (shouldDeleteFileAfterUndoWindow) {
        val file = context.appOwnedLibraryFile(item)
        if (file == null || !file.exists()) {
            onFeedback(LibraryFileUnavailableMessage)
            return
        }
    }
    onDelete(item)
    coroutineScope.launch {
        val result = snackbarHostState.showSnackbar(
            message = "已删除 ${item.title}",
            actionLabel = "撤销",
        )
        if (result == SnackbarResult.ActionPerformed) {
            onRestore(item)
            return@launch
        }
        if (shouldDeleteFileAfterUndoWindow) {
            val deleted = context.deleteAppOwnedLibraryFile(
                item = item,
                onDelete = { _ -> },
                onFeedback = onFeedback,
            )
            if (!deleted) {
                onRestore(item)
            }
        }
    }
}

private fun Context.openLibraryItem(
    item: AndroidLibraryItem,
    onFeedback: (String) -> Unit,
) {
    val uri = exportableLibraryUri(item)
    if (uri == null) {
        onFeedback(LibraryFileUnavailableMessage)
        return
    }
    val intent = Intent(Intent.ACTION_VIEW)
        .setDataAndType(uri, item.mimeTypeForIntent)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        .apply {
            clipData = ClipData.newUri(contentResolver, item.title, uri)
        }
    runCatching {
        startActivity(Intent.createChooser(intent, "打开文件"))
    }.onSuccess {
        onFeedback(LibraryOpenStartedMessage)
    }.onFailure {
        onFeedback(LibraryOpenFailedMessage)
    }
}

private fun Context.shareLibraryItem(
    item: AndroidLibraryItem,
    onFeedback: (String) -> Unit,
) {
    val uri = exportableLibraryUri(item)
    if (uri == null) {
        onFeedback(LibraryFileUnavailableMessage)
        return
    }
    val intent = Intent(Intent.ACTION_SEND)
        .setType(item.mimeTypeForIntent)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        .apply {
            clipData = ClipData.newUri(contentResolver, item.title, uri)
        }
    runCatching {
        startActivity(Intent.createChooser(intent, item.title))
    }.onSuccess {
        onFeedback(LibraryShareStartedMessage)
    }.onFailure {
        onFeedback(LibraryShareFailedMessage)
    }
}

private fun Context.saveLibraryItemCopy(
    item: AndroidLibraryItem,
    onSaveCopy: (AndroidLibraryItem) -> Unit,
    onFeedback: (String) -> Unit,
) {
    if (exportableLibraryUri(item) == null) {
        onFeedback(LibraryFileUnavailableMessage)
        return
    }
    onSaveCopy(item)
}

private fun Context.deleteAppOwnedLibraryFile(
    item: AndroidLibraryItem,
    onDelete: (AndroidLibraryItem) -> Unit,
    onFeedback: (String) -> Unit,
): Boolean {
    val file = appOwnedLibraryFile(item)
    if (file == null) {
        onFeedback(LibraryFileUnavailableMessage)
        return false
    }
    if (!file.exists()) {
        onFeedback(LibraryFileUnavailableMessage)
        return false
    }
    if (!file.delete()) {
        onFeedback(LibraryFileDeleteFailedMessage)
        return false
    }
    onDelete(item)
    onFeedback(LibraryFileDeletedMessage)
    return true
}

private const val LibraryFileUnavailableMessage = "文件不可用，请重新导入后再试。"
private const val LibraryOpenStartedMessage = "正在打开文件。"
private const val LibraryOpenFailedMessage = "没有可用的应用打开这个文件。"
private const val LibraryShareStartedMessage = "已打开分享面板。"
private const val LibraryShareFailedMessage = "无法分享这个文件。"
private const val LibraryCopySavedMessage = "已保存副本。"
private const val LibraryCopyFailedMessage = "副本保存失败，请重试。"
private const val LibraryFileDeletedMessage = "文件已删除。"
private const val LibraryFileDeleteFailedMessage = "文件删除失败，请重试。"

private fun Context.androidNotificationPermissionState(): AndroidNotificationPermissionState =
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        AndroidNotificationPermissionState.NOT_REQUIRED
    } else if (ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    ) {
        AndroidNotificationPermissionState.GRANTED
    } else {
        AndroidNotificationPermissionState.UNKNOWN
    }

private fun Context.openAppNotificationSettings() {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    startActivity(intent)
}

private fun Context.appOwnedLibraryFile(item: AndroidLibraryItem): File? {
    val storageUri = item.storageUri ?: return null
    val rawUri = Uri.parse(storageUri)
    if (rawUri.scheme != "android-owned") {
        return null
    }
    val fileName = rawUri.schemeSpecificPart.trimStart('/')
    if (fileName.isBlank() || fileName.contains("/") || fileName.contains("..")) {
        return null
    }
    val file = File(File(filesDir, "downloads"), fileName).canonicalFile
    val downloadsDirectory = File(filesDir, "downloads").canonicalFile
    if (!file.toPath().startsWith(downloadsDirectory.toPath())) {
        return null
    }
    return file
}

private fun Context.exportableLibraryUri(item: AndroidLibraryItem): Uri? {
    val storageUri = item.storageUri ?: return null
    val rawUri = Uri.parse(storageUri)
    if (rawUri.scheme == "content") {
        return rawUri
    }
    if (rawUri.scheme == "android-owned") {
        val fileName = rawUri.schemeSpecificPart.trimStart('/')
        if (fileName.isBlank() || fileName.contains("/") || fileName.contains("..")) {
            return null
        }
        val output = File(File(filesDir, "downloads"), fileName).canonicalFile
        val downloadsDirectory = File(filesDir, "downloads").canonicalFile
        if (!output.toPath().startsWith(downloadsDirectory.toPath()) || !output.exists()) {
            return null
        }
        return FileProvider.getUriForFile(
            this,
            "${packageName}.files",
            output,
        )
    }
    if (rawUri.scheme != "file") {
        return null
    }
    val rawFile = File(rawUri.path ?: return null).canonicalFile
    val context = this
    val downloadsDirectory = File(context.filesDir, "downloads").canonicalFile
    if (!rawFile.toPath().startsWith(downloadsDirectory.toPath()) || !rawFile.exists()) {
        return null
    }
    return FileProvider.getUriForFile(
        this,
        "${packageName}.files",
        rawFile,
    )
}

private fun Context.androidTaskRepository(): TaskRepository =
    JsonTaskRepository(File(File(filesDir, "tasks"), "tasks.json").toPath())

private fun Context.copyLibraryItemBytes(source: Uri, destination: Uri) {
    val input = contentResolver.openInputStream(source) ?: throw IOException("Unable to open source")
    input.use { sourceStream ->
        val output = contentResolver.openOutputStream(destination)
            ?: throw IOException("Unable to open destination")
        output.use { destinationStream ->
            sourceStream.copyTo(destinationStream)
        }
    }
}

private val AndroidLibraryItem.mimeTypeForIntent: String
    get() = when (artifacts.firstOrNull()?.kind) {
        com.moongate.mobile.domain.AndroidLibraryArtifactKind.TRANSLATED_SUBTITLE -> "text/*"
        else -> "video/*"
    }

private val AndroidLibraryItem.suggestedCopyFileName: String
    get() = artifacts.firstOrNull()?.displayName
        ?.takeIf { it.isNotBlank() }
        ?: "$title.moongate"

private fun Intent.sharedHttpUrl(): String? {
    if (action != Intent.ACTION_SEND) {
        return null
    }
    if (type != "text/plain") {
        return null
    }
    return getStringExtra(Intent.EXTRA_TEXT)?.firstSharedHttpUrl()
}

private val AndroidTranslationCredentialReference = SecureCredentialReference(
    service = "translation.android.cloud",
    account = "default",
    displayName = "API key 已安全保存",
)

private fun Uri.androidImportID(): String {
    val raw = toString().ifBlank { "selected-${hashCode()}" }
    val digest = MessageDigest.getInstance("SHA-256")
        .digest(raw.toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { "%02x".format(it) }
    return "doc-${digest.take(24)}"
}

private fun Uri.displayName(context: Context): String {
    context.contentResolver.query(
        this,
        arrayOf(OpenableColumns.DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor ->
        if (cursor.moveToFirst()) {
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0) {
                val value = cursor.getString(index)
                if (!value.isNullOrBlank()) {
                    return value
                }
            }
        }
    }
    return lastPathSegment
        ?.substringAfterLast('/')
        ?.takeIf { it.isNotBlank() }
        ?: "导入的视频"
}

private fun Uri.byteCount(context: Context): Long? {
    context.contentResolver.query(
        this,
        arrayOf(OpenableColumns.SIZE),
        null,
        null,
        null,
    )?.use { cursor ->
        if (cursor.moveToFirst()) {
            val index = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (index >= 0 && !cursor.isNull(index)) {
                return cursor.getLong(index)
            }
        }
    }
    return null
}

private val PreviewBackgroundWorkCoordinator = AndroidBackgroundWorkCoordinator.blocked()

private object PreviewCredentialStore : SecureCredentialStore {
    override suspend fun saveCredential(
        secret: String,
        reference: SecureCredentialReference,
    ): SecureCredentialReference = reference

    override suspend fun deleteCredential(reference: SecureCredentialReference) = Unit

    override suspend fun hasCredential(reference: SecureCredentialReference): Boolean = false

    override suspend fun credential(reference: SecureCredentialReference): String? = null
}
