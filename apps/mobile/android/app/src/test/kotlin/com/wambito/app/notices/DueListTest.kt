package com.wambito.app.notices

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.LocalDate

@RunWith(RobolectricTestRunner::class)
class DueListTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @After
    fun tearDown() = DueList.clear(context)

    @Test
    fun `replace twice keeps only the second list`() {
        DueList.replace(context, "u1", listOf("2026-10-30" to listOf("Arriendo"), "2026-11-03" to listOf("Gym")))
        DueList.replace(context, "u1", listOf("2026-11-03" to listOf("Spotify", "Gym")))

        assertEquals(emptyList<String>(), DueList.namesOn(context, LocalDate.parse("2026-10-30")))
        assertEquals(listOf("Spotify", "Gym"), DueList.namesOn(context, LocalDate.parse("2026-11-03")))
    }

    @Test
    fun `the list belongs to the account it was read for`() {
        assertNull(DueList.owner(context))
        DueList.replace(context, "u1", listOf("2026-10-30" to listOf("Arriendo")))
        assertEquals("u1", DueList.owner(context))
    }

    @Test
    fun `clear forgets the days and the owner`() {
        DueList.replace(context, "u1", listOf("2026-10-30" to listOf("Arriendo")))
        DueList.clear(context)

        assertNull(DueList.owner(context))
        assertEquals(emptyList<String>(), DueList.namesOn(context, LocalDate.parse("2026-10-30")))
    }

    @Test
    fun `a day nobody listed has no names`() {
        DueList.replace(context, "u1", emptyList())
        assertEquals(emptyList<String>(), DueList.namesOn(context, LocalDate.parse("2026-10-30")))
    }
}
