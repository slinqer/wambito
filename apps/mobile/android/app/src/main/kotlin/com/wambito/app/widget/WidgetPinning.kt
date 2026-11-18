package com.wambito.app.widget

/** The AppWidget providers the manifest declares (the receivers, not the Glance widgets), for pinning and counting. */
object WidgetPinning {
    val receivers: List<Class<*>> = listOf(
        WambitoSmallWidgetReceiver::class.java,
        WambitoMediumWidgetReceiver::class.java,
    )
}
