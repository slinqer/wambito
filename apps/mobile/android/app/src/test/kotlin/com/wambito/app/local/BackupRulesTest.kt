package com.wambito.app.local

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * The vault (lib/local: `files/vault/`, the app support folder's `vault`) and the secure storage
 * that holds the data key never leave the phone in a backup or a device transfer.
 */
class BackupRulesTest {
    private val xml = File("src/main/res/xml")
    private val manifest = File("src/main/AndroidManifest.xml")

    private fun excludes(file: String, parent: String?): Set<Pair<String, String>> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(xml, file))
        val scope = if (parent == null) {
            doc.documentElement
        } else {
            val found = doc.getElementsByTagName(parent)
            assertEquals("one <$parent> in $file", 1, found.length)
            found.item(0) as Element
        }
        val list = scope.getElementsByTagName("exclude")
        return (0 until list.length).map {
            val e = list.item(it) as Element
            e.getAttribute("domain") to e.getAttribute("path")
        }.toSet()
    }

    private val vault = "file" to "vault"
    private val keys = "sharedpref" to "FlutterSecureStorage.xml"
    private val wrappedKey = "sharedpref" to "FlutterSecureKeyStorage.xml"

    @Test
    fun `the Android 12 rules exclude the vault and the secure storage from cloud backup and transfer`() {
        for (scope in listOf("cloud-backup", "device-transfer")) {
            val found = excludes("data_extraction_rules.xml", scope)
            assertTrue("$scope: $found", found.containsAll(listOf(vault, keys, wrappedKey)))
        }
    }

    @Test
    fun `the older full backup rules exclude the same files`() {
        val found = excludes("backup_rules.xml", null)
        assertTrue(found.toString(), found.containsAll(listOf(vault, keys, wrappedKey)))
    }

    @Test
    fun `the manifest points at both rule files`() {
        val text = manifest.readText()
        assertTrue(text.contains("android:dataExtractionRules=\"@xml/data_extraction_rules\""))
        assertTrue(text.contains("android:fullBackupContent=\"@xml/backup_rules\""))
    }
}
