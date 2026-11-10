package com.berkant.tag_stats

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

/**
 * Records every distinct Martı TAG screen (texts + node tree) to the screens log.
 * Other apps are only noted by package name so the target app can be identified.
 */
class MartiAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var snapshotScheduled = false
    private var pendingEvent = ""
    private var lastHash = 0

    override fun onServiceConnected() {
        super.onServiceConnected()
        SharedState.a11yConnected = true
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        SharedState.a11yConnected = false
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        SharedState.a11yConnected = false
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            Prefs.addSeen(this, pkg)
            if (pkg != "com.android.systemui") SharedState.foregroundPkg = pkg
        }
        if (!Prefs.isTarget(this, pkg)) return

        SharedState.lastTargetEventAt = System.currentTimeMillis()
        pendingEvent = eventName(event.eventType)
        if (!snapshotScheduled) {
            snapshotScheduled = true
            handler.postDelayed({
                snapshotScheduled = false
                snapshot(pkg, pendingEvent)
            }, 250)
        }
    }

    private fun snapshot(pkg: String, event: String) {
        val roots = mutableListOf<AccessibilityNodeInfo>()
        try {
            windows?.forEach { w -> w.root?.takeIf { it.packageName?.toString() == pkg }?.let(roots::add) }
        } catch (_: Exception) {
        }
        if (roots.isEmpty()) rootInActiveWindow?.takeIf { it.packageName?.toString() == pkg }?.let(roots::add)
        if (roots.isEmpty()) return

        val texts = mutableListOf<String>()
        val nodes = JSONArray()
        val signature = StringBuilder()
        var count = 0
        for (root in roots) count = walk(root, 0, texts, nodes, signature, count)

        val hash = signature.toString().hashCode()
        if (hash == lastHash) return
        lastHash = hash
        LogStore.writeScreen(this, "a11y", pkg, event, texts, nodes)
    }

    private fun walk(
        node: AccessibilityNodeInfo,
        depth: Int,
        texts: MutableList<String>,
        nodes: JSONArray,
        signature: StringBuilder,
        countIn: Int,
    ): Int {
        if (depth > MAX_DEPTH || countIn > MAX_NODES) return countIn
        var count = countIn + 1

        val text = node.text?.toString()?.trim().orEmpty()
        val desc = node.contentDescription?.toString()?.trim().orEmpty()
        val state = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            node.stateDescription?.toString()?.trim().orEmpty()
        } else ""
        val id = node.viewIdResourceName.orEmpty()

        if (text.isNotEmpty() || desc.isNotEmpty() || state.isNotEmpty() || id.isNotEmpty() || node.isCheckable) {
            val r = Rect().also(node::getBoundsInScreen)
            val json = JSONObject()
                .put("d", depth)
                .put("c", node.className?.toString()?.substringAfterLast('.') ?: "")
                .put("b", JSONArray(listOf(r.left, r.top, r.right, r.bottom)))
            if (text.isNotEmpty()) json.put("t", text)
            if (desc.isNotEmpty()) json.put("cd", desc)
            if (state.isNotEmpty()) json.put("sd", state)
            if (id.isNotEmpty()) json.put("id", id)
            if (node.isCheckable) json.put("chk", node.isChecked)
            if (node.isClickable) json.put("clk", true)
            if (node.isSelected) json.put("sel", true)
            nodes.put(json)

            if (text.isNotEmpty()) texts.add(text)
            if (desc.isNotEmpty() && desc != text) texts.add(desc)
            signature.append(text).append('|').append(desc).append('|').append(state)
                .append('|').append(node.isChecked).append(';')
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            count = walk(child, depth + 1, texts, nodes, signature, count)
        }
        return count
    }

    private fun eventName(type: Int) = when (type) {
        AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> "state"
        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> "content"
        AccessibilityEvent.TYPE_WINDOWS_CHANGED -> "windows"
        else -> type.toString()
    }

    companion object {
        private const val MAX_DEPTH = 60
        private const val MAX_NODES = 1500
    }
}
