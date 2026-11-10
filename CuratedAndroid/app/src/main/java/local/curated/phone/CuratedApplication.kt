package local.curated.phone

import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.snapshots.Snapshot
import androidx.car.app.connection.CarConnection
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class CuratedApplication : Application() {
    lateinit var state: AppState
        private set
    lateinit var playback: Playback
        private set

    override fun onCreate() {
        super.onCreate()
        deliverStateChangesWithoutWindow()
        state = AppState(this)
        playback = Playback(this, state)
        CarConnection(this).type.observeForever { type ->
            playback.carConnectionChanged(type == CarConnection.CONNECTION_TYPE_PROJECTION || type == CarConnection.CONNECTION_TYPE_NATIVE)
        }
    }
}

/**
 * `snapshotFlow` only hears of changes once they're announced, which Compose starts doing when it first draws. Started by
 * Android Auto, the app has no window, so nothing would ever draw.
 */
private fun deliverStateChangesWithoutWindow() {
    val handler = Handler(Looper.getMainLooper())
    var scheduled = false
    Snapshot.registerGlobalWriteObserver {
        if (!scheduled) {
            scheduled = true
            handler.post {
                scheduled = false
                Snapshot.sendApplyNotifications()
            }
        }
    }
}

val Context.curated: CuratedApplication get() = applicationContext as CuratedApplication

/** Automatic sync: runs on unmetered Wi-Fi while charging (see AppState.updateAutoSync). */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val state = applicationContext.curated.state
        if (state.pairing == null) return Result.success()
        state.sync()
        return Result.success()
    }

    companion object {
        const val NAME = "curated-sync"
    }
}
