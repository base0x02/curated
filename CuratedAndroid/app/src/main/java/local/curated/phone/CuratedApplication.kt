package local.curated.phone

import android.app.Application
import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class CuratedApplication : Application() {
    lateinit var state: AppState
        private set
    lateinit var playback: Playback
        private set

    override fun onCreate() {
        super.onCreate()
        state = AppState(this)
        playback = Playback(this, state)
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
