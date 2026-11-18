package com.wambito.app.widget

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pinned and counted classes are the appwidget providers the manifest registers. */
class WidgetPinningTest {
    @Test
    fun receiversAreTheManifestsAppWidgetProviders() {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/AndroidManifest.xml"))
        val receivers = doc.getElementsByTagName("receiver")
        val providers = (0 until receivers.length).map { receivers.item(it) }.filter { node ->
            val metas = (node as org.w3c.dom.Element).getElementsByTagName("meta-data")
            (0 until metas.length).any {
                (metas.item(it) as org.w3c.dom.Element).getAttribute("android:name") ==
                    "android.appwidget.provider"
            }
        }.map { (it as org.w3c.dom.Element).getAttribute("android:name") }
        assertTrue(providers.isNotEmpty())
        val ours = WidgetPinning.receivers.map { ".widget." + it.simpleName }
        assertEquals(providers.sorted(), ours.sorted())
    }
}
