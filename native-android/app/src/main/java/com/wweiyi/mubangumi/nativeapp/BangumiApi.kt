package com.wweiyi.mubangumi.nativeapp

import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class BangumiApi {
    private val apiBaseUrl = "https://api.bgm.tv/v0"
    private val nextBaseUrl = "https://next.bgm.tv/p1"

    suspend fun getMe(token: String): BangumiUser =
        requestObject("$apiBaseUrl/me", token = token).toBangumiUser()

    suspend fun getUser(username: String, token: String? = null): BangumiUser {
        val encoded = URLEncoder.encode(username, Charsets.UTF_8.name())
        return requestObject("$apiBaseUrl/users/$encoded", token = token).toBangumiUser()
    }

    suspend fun getCollections(username: String, token: String): List<CollectionItem> = withContext(Dispatchers.IO) {
        val result = mutableListOf<CollectionItem>()
        var offset = 0
        var total: Int
        do {
            val encoded = URLEncoder.encode(username, Charsets.UTF_8.name())
            val page = requestObject(
                "$apiBaseUrl/users/$encoded/collections?limit=100&offset=$offset",
                token = token,
            )
            val data = page.optArray("data") ?: JSONArray()
            repeat(data.length()) { index ->
                val item = data.optJSONObject(index)
                if (item != null) result += item.toCollectionItem()
            }
            total = page.optInt("total", result.size)
            offset += data.length()
        } while (offset < total && offset < 1000)
        result.sortedByDescending { it.updatedAt }
    }

    suspend fun browseSubjects(
        type: SubjectType = SubjectType.Anime,
        limit: Int = 24,
        year: Int? = null,
        month: Int? = null,
    ): List<Subject> {
        val query = buildList {
            add("type=${type.value}")
            add("sort=rank")
            add("limit=$limit")
            add("offset=0")
            if (year != null) add("year=$year")
            if (month != null) add("month=$month")
        }.joinToString("&")
        return parseSubjectPage(requestObject("$apiBaseUrl/subjects?$query"))
    }

    suspend fun searchSubjects(keyword: String, type: SubjectType): List<Subject> {
        val body = JSONObject()
            .put("keyword", keyword)
            .put("sort", "match")
            .put(
                "filter",
                JSONObject()
                    .put("type", JSONArray().put(type.value))
                    .put("nsfw", false),
            )
        return parseSubjectPage(
            requestObject(
                "$apiBaseUrl/search/subjects?limit=36&offset=0",
                method = "POST",
                body = body,
            ),
        )
    }

    suspend fun getSubject(subjectId: Int): Subject =
        requestObject("$apiBaseUrl/subjects/$subjectId").toSubject()

    suspend fun updateCollection(
        subjectId: Int,
        status: CollectionStatus,
        token: String,
        rate: Int = 0,
        comment: String = "",
    ) {
        val body = JSONObject().put("type", status.value)
        if (rate > 0) body.put("rate", rate)
        if (comment.isNotBlank()) body.put("comment", comment)
        requestText(
            "$apiBaseUrl/users/-/collections/$subjectId",
            method = "POST",
            token = token,
            body = body,
        )
    }

    suspend fun markNextEpisode(subjectId: Int, currentProgress: Int, token: String) {
        val page = requestObject(
            "$apiBaseUrl/episodes?subject_id=$subjectId&type=0&limit=100&offset=0",
            token = token,
        )
        val episodes = page.optArray("data") ?: JSONArray()
        var targetId = 0
        repeat(episodes.length()) { index ->
            val episode = episodes.optJSONObject(index) ?: return@repeat
            val number = episode.optDouble("ep", 0.0).toInt()
            if (number == currentProgress + 1) targetId = episode.optInt("id")
        }
        if (targetId <= 0) throw BangumiApiException("没有找到下一集", 404)
        requestText(
            "$apiBaseUrl/users/-/collections/-/episodes/$targetId",
            method = "PUT",
            token = token,
            body = JSONObject().put("type", 2),
        )
    }

    suspend fun getTopics(kind: String = "group"): List<CommunityTopic> {
        val path = if (kind == "subject") "subjects/-/topics" else "groups/-/topics?mode=all"
        val page = requestObject("$nextBaseUrl/$path&limit=30&offset=0".replace("topics&", "topics?"))
        val data = page.optArray("data") ?: JSONArray()
        return buildList {
            repeat(data.length()) { index ->
                val json = data.optJSONObject(index) ?: return@repeat
                val id = json.optInt("id")
                val title = json.optString("title")
                if (id <= 0 || title.isBlank()) return@repeat
                val creator = json.optObject("creator")
                val context = json.optObject(if (kind == "subject") "subject" else "group")
                val sourceTitle = if (kind == "subject") {
                    context?.optString("name_cn").orEmpty().ifBlank { context?.optString("name").orEmpty() }
                } else {
                    context?.optString("title").orEmpty()
                }
                add(
                    CommunityTopic(
                        id = id,
                        kind = kind,
                        title = title,
                        sourceTitle = sourceTitle,
                        author = creator?.optString("nickname").orEmpty().ifBlank {
                            creator?.optString("username").orEmpty()
                        },
                        avatarUrl = creator?.optObject("avatar")?.optString("small").orEmpty(),
                        replyCount = json.optInt("replyCount"),
                        updatedAt = json.optString("updatedAt").replace('T', ' ').take(16),
                        webUrl = "https://bgm.tv/$kind/topic/$id",
                    ),
                )
            }
        }
    }

    suspend fun getTopicDetail(topic: CommunityTopic): CommunityTopicDetail {
        val area = if (topic.kind == "subject") "subjects" else "groups"
        val json = requestObject("$nextBaseUrl/$area/-/topics/${topic.id}")
        val replies = json.optArray("replies") ?: JSONArray()
        val posts = mutableListOf<CommunityPost>()
        fun appendPost(value: JSONObject, nested: Boolean) {
            val creator = value.optObject("creator")
            val avatar = creator?.optObject("avatar")
            val rawContent = value.optString("content")
            val content = rawContent
                .replace(Regex("\\[[^]]*]"), "")
                .replace(Regex("\\n{3,}"), "\\n\\n")
                .trim()
                .ifBlank { if (value.optInt("state") != 0) "（该回复已删除或不可见）" else "（无文字内容）" }
            posts += CommunityPost(
                id = value.opt("id")?.toString().orEmpty(),
                author = creator?.optString("nickname").orEmpty().ifBlank { creator?.optString("username").orEmpty() },
                avatarUrl = avatar?.optString("small").orEmpty(),
                content = content,
                createdAt = formatEpoch(value.optLong("createdAt")),
                nested = nested,
            )
        }
        repeat(replies.length()) { index ->
            val reply = replies.optJSONObject(index) ?: return@repeat
            appendPost(reply, nested = false)
            val children = reply.optArray("replies") ?: JSONArray()
            repeat(children.length()) { childIndex ->
                children.optJSONObject(childIndex)?.let { appendPost(it, nested = true) }
            }
        }
        val source = json.optObject(if (topic.kind == "subject") "subject" else "group")
        val sourceTitle = if (topic.kind == "subject") {
            source?.optString("name_cn").orEmpty().ifBlank { source?.optString("name").orEmpty() }
        } else {
            source?.optString("title").orEmpty()
        }
        return CommunityTopicDetail(
            title = json.optString("title").ifBlank { topic.title },
            sourceTitle = sourceTitle.ifBlank { topic.sourceTitle },
            posts = posts,
        )
    }

    suspend fun getFriends(username: String, token: String): List<BangumiUser> {
        val encoded = URLEncoder.encode(username, Charsets.UTF_8.name())
        val page = requestObject("$nextBaseUrl/users/$encoded/friends?limit=40&offset=0", token = token)
        val data = page.optArray("data") ?: JSONArray()
        return buildList {
            repeat(data.length()) { index ->
                val item = data.optJSONObject(index) ?: return@repeat
                val user = item.toBangumiUser()
                if (user.username.isNotBlank()) add(user)
            }
        }
    }

    suspend fun getNotices(token: String): List<BangumiNoticeNative> {
        val page = requestObject("$nextBaseUrl/notify?limit=40", token = token)
        val data = page.optArray("data") ?: JSONArray()
        return buildList {
            repeat(data.length()) { index ->
                val item = data.optJSONObject(index) ?: return@repeat
                val id = item.optInt("id")
                if (id <= 0) return@repeat
                val sender = item.optObject("sender")?.let { it.toBangumiUser() }
                add(
                    BangumiNoticeNative(
                        id = id,
                        title = item.optString("title").ifBlank { "新的电波提醒" },
                        type = item.optInt("type"),
                        mainId = item.optInt("mainID"),
                        relatedId = item.optInt("relatedID"),
                        unread = item.optBoolean("unread"),
                        createdAt = formatEpoch(item.optLong("createdAt")),
                        sender = sender,
                    ),
                )
            }
        }
    }

    suspend fun markNoticesRead(token: String, ids: List<Int> = emptyList()) {
        val body = JSONObject()
        if (ids.isNotEmpty()) {
            val values = JSONArray()
            ids.forEach(values::put)
            body.put("id", values)
        }
        requestText("$nextBaseUrl/clear-notify", method = "POST", token = token, body = body)
    }

    private fun parseSubjectPage(page: JSONObject): List<Subject> {
        val data = page.optArray("data") ?: JSONArray()
        return buildList {
            repeat(data.length()) { index ->
                val item = data.optJSONObject(index)
                if (item != null) add(item.toSubject())
            }
        }
    }

    private fun formatEpoch(value: Long): String {
        if (value <= 0) return ""
        return runCatching {
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
                .withZone(ZoneId.systemDefault())
                .format(Instant.ofEpochSecond(value))
        }.getOrDefault(value.toString())
    }

    private suspend fun requestObject(
        url: String,
        method: String = "GET",
        token: String? = null,
        body: JSONObject? = null,
    ): JSONObject = JSONObject(requestText(url, method, token, body))

    private suspend fun requestText(
        url: String,
        method: String = "GET",
        token: String? = null,
        body: JSONObject? = null,
    ): String = withContext(Dispatchers.IO) {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 15_000
            connection.readTimeout = 25_000
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("User-Agent", "MuBangumi/1.0-native (Android)")
            if (!token.isNullOrBlank()) connection.setRequestProperty("Authorization", "Bearer $token")
            if (body != null) {
                connection.doOutput = true
                connection.outputStream.bufferedWriter(Charsets.UTF_8).use { it.write(body.toString()) }
            }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader()?.use(BufferedReader::readText).orEmpty()
            if (code !in 200..299) {
                val message = runCatching {
                    val error = JSONObject(response)
                    error.optString("description").ifBlank { error.optString("message") }
                }.getOrNull().orEmpty().ifBlank { "请求失败（HTTP $code）" }
                throw BangumiApiException(message, code)
            }
            response.ifBlank { "{}" }
        } finally {
            connection.disconnect()
        }
    }
}

class BangumiApiException(message: String, val statusCode: Int) : Exception(message)
