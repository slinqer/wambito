package com.wambito.app.capture

/** The apps whose notifications become captures: [wire] is the API's `source`. */
enum class CaptureSource(val wire: String, val packageName: String) {
    REVOLUT("revolut", "com.revolut.revolut"),
    GOOGLE_WALLET("google_wallet", "com.google.android.apps.walletnfcrel"),
    ACTIVOBANK("activobank", "wit.android.bcpBankingApp.activoBank"),
    ;

    companion object {
        fun forPackage(name: String): CaptureSource? = entries.firstOrNull { it.packageName == name }

        fun forWire(wire: String): CaptureSource? = entries.firstOrNull { it.wire == wire }
    }
}
