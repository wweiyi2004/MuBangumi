package com.wweiyi.mubangumi.nativeapp

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelsTest {
    @Test
    fun subjectParserPrefersChineseNameAndLargeImage() {
        val subject = JSONObject(
            """
            {
              "id": 42,
              "type": 2,
              "name": "Example",
              "name_cn": "示例动画",
              "images": {"large": "https://example.com/large.jpg"},
              "rating": {"score": 8.4, "rank": 123},
              "tags": [{"name": "科幻"}, {"name": "原创"}]
            }
            """.trimIndent(),
        ).toSubject()

        assertEquals("示例动画", subject.displayName)
        assertEquals("https://example.com/large.jpg", subject.imageUrl)
        assertEquals(8.4, subject.score, 0.001)
        assertEquals(listOf("科幻", "原创"), subject.tags)
    }

    @Test
    fun collectionParserKeepsStatusAndProgress() {
        val collection = JSONObject(
            """
            {
              "subject_id": 42,
              "type": 3,
              "rate": 9,
              "ep_status": 7,
              "subject": {"id": 42, "type": 2, "name_cn": "示例动画", "eps": 12}
            }
            """.trimIndent(),
        ).toCollectionItem()

        assertEquals(CollectionStatus.Doing, collection.status)
        assertEquals(7, collection.epStatus)
        assertEquals(12, collection.subject.episodeCount)
    }

    @Test
    fun collectionLabelsFollowSubjectType() {
        assertEquals("在看", CollectionStatus.Doing.label(SubjectType.Anime))
        assertEquals("在读", CollectionStatus.Doing.label(SubjectType.Book))
        assertEquals("想玩", CollectionStatus.Wish.label(SubjectType.Game))
        assertEquals("听过", CollectionStatus.Done.label(SubjectType.Music))
    }
}
