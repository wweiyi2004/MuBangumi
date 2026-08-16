package com.wweiyi.mubangumi.nativeapp

import org.json.JSONArray
import org.json.JSONObject

enum class SubjectType(val value: Int, val label: String, val verb: String) {
    Book(1, "书籍", "读"),
    Anime(2, "动画", "看"),
    Music(3, "音乐", "听"),
    Game(4, "游戏", "玩"),
    Real(6, "三次元", "看");

    companion object {
        fun fromValue(value: Int) = entries.firstOrNull { it.value == value } ?: Anime
    }
}

enum class CollectionStatus(val value: Int) {
    Wish(1),
    Done(2),
    Doing(3),
    OnHold(4),
    Dropped(5);

    fun label(type: SubjectType = SubjectType.Anime) = when (this) {
        Wish -> "想${type.verb}"
        Done -> "${type.verb}过"
        Doing -> "在${type.verb}"
        OnHold -> "搁置"
        Dropped -> "抛弃"
    }

    companion object {
        fun fromValue(value: Int) = entries.firstOrNull { it.value == value } ?: Wish
    }
}

data class BangumiUser(
    val id: Int,
    val username: String,
    val nickname: String,
    val avatarUrl: String,
    val sign: String,
) {
    val displayName: String get() = nickname.ifBlank { username }
}

data class Subject(
    val id: Int,
    val type: SubjectType,
    val name: String,
    val nameCn: String,
    val imageUrl: String,
    val summary: String,
    val episodeCount: Int,
    val volumeCount: Int,
    val score: Double,
    val rank: Int,
    val date: String,
    val collectionTotal: Int,
    val tags: List<String>,
    val platform: String,
) {
    val displayName: String get() = nameCn.ifBlank { name }
}

data class CollectionItem(
    val subjectId: Int,
    val status: CollectionStatus,
    val rate: Int,
    val epStatus: Int,
    val volStatus: Int,
    val comment: String,
    val updatedAt: String,
    val subject: Subject,
)

data class CommunityTopic(
    val id: Int,
    val kind: String,
    val title: String,
    val sourceTitle: String,
    val author: String,
    val avatarUrl: String,
    val replyCount: Int,
    val updatedAt: String,
    val webUrl: String,
)

data class CommunityTopicDetail(
    val title: String,
    val sourceTitle: String,
    val posts: List<CommunityPost>,
)

data class CommunityPost(
    val id: String,
    val author: String,
    val avatarUrl: String,
    val content: String,
    val createdAt: String,
    val nested: Boolean,
)

data class BangumiNoticeNative(
    val id: Int,
    val title: String,
    val type: Int,
    val mainId: Int,
    val relatedId: Int,
    val unread: Boolean,
    val createdAt: String,
    val sender: BangumiUser?,
)

fun JSONObject.toBangumiUser(): BangumiUser {
    val avatar = optObject("avatar")
    return BangumiUser(
        id = optInt("id"),
        username = optString("username"),
        nickname = optString("nickname").ifBlank { optString("username") },
        avatarUrl = avatar?.optString("large").orEmpty().ifBlank {
            avatar?.optString("medium").orEmpty()
        },
        sign = optString("sign"),
    )
}

fun JSONObject.toSubject(): Subject {
    val images = optObject("images")
    val rating = optObject("rating")
    val collection = optObject("collection")
    val tagsJson = optArray("tags")
    val tags = buildList {
        if (tagsJson != null) {
            repeat(minOf(tagsJson.length(), 8)) { index ->
                val item = tagsJson.opt(index)
                val value = if (item is JSONObject) item.optString("name") else item?.toString().orEmpty()
                if (value.isNotBlank()) add(value)
            }
        }
    }
    return Subject(
        id = optInt("id"),
        type = SubjectType.fromValue(optInt("type", optInt("subject_type", 2))),
        name = optString("name"),
        nameCn = optString("name_cn"),
        imageUrl = images?.optString("large").orEmpty().ifBlank {
            images?.optString("common").orEmpty().ifBlank { images?.optString("medium").orEmpty() }
        },
        summary = optString("summary").ifBlank { optString("short_summary") },
        episodeCount = optInt("eps", optInt("total_episodes")),
        volumeCount = optInt("volumes"),
        score = rating?.optDouble("score")?.takeUnless { it.isNaN() } ?: optDouble("score", 0.0),
        rank = rating?.optInt("rank") ?: optInt("rank"),
        date = optString("date").ifBlank { optString("air_date") },
        collectionTotal = collection?.optInt("total") ?: optInt("collection_total"),
        tags = tags,
        platform = optString("platform"),
    )
}

fun JSONObject.toCollectionItem(): CollectionItem {
    val subjectJson = optObject("subject") ?: JSONObject()
    return CollectionItem(
        subjectId = optInt("subject_id", subjectJson.optInt("id")),
        status = CollectionStatus.fromValue(optInt("type")),
        rate = optInt("rate"),
        epStatus = optInt("ep_status"),
        volStatus = optInt("vol_status"),
        comment = optString("comment"),
        updatedAt = optString("updated_at"),
        subject = subjectJson.toSubject(),
    )
}

fun JSONObject.optObject(key: String): JSONObject? = opt(key) as? JSONObject

fun JSONObject.optArray(key: String): JSONArray? = opt(key) as? JSONArray
