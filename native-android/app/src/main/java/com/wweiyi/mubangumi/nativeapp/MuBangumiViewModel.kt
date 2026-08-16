package com.wweiyi.mubangumi.nativeapp

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.time.LocalDate
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

enum class SessionPhase { Booting, SignedOut, SignedIn }

data class AppState(
    val phase: SessionPhase = SessionPhase.Booting,
    val user: BangumiUser? = null,
    val token: String = "",
    val collections: List<CollectionItem> = emptyList(),
    val discover: List<Subject> = emptyList(),
    val searchResults: List<Subject> = emptyList(),
    val topics: List<CommunityTopic> = emptyList(),
    val selectedTopic: CommunityTopic? = null,
    val topicDetail: CommunityTopicDetail? = null,
    val friends: List<BangumiUser> = emptyList(),
    val notices: List<BangumiNoticeNative> = emptyList(),
    val selectedSubject: Subject? = null,
    val isRefreshing: Boolean = false,
    val isDiscoverLoading: Boolean = false,
    val isCommunityLoading: Boolean = false,
    val isTopicLoading: Boolean = false,
    val isFriendsLoading: Boolean = false,
    val isNoticesLoading: Boolean = false,
    val isDetailLoading: Boolean = false,
    val isDarkMode: Boolean = false,
    val isDemo: Boolean = false,
    val message: String? = null,
)

class MuBangumiViewModel(application: Application) : AndroidViewModel(application) {
    private val api = BangumiApi()
    private val preferences = application.getSharedPreferences("mubangumi_native", 0)

    var state by mutableStateOf(
        AppState(isDarkMode = preferences.getBoolean("dark_mode", false)),
    )
        private set

    init {
        val token = preferences.getString("access_token", null).orEmpty()
        if (token.isBlank()) {
            state = state.copy(phase = SessionPhase.SignedOut)
        } else {
            authenticate(token, persist = false)
        }
    }

    fun signIn(rawToken: String) {
        val token = rawToken.trim().replace(Regex("^Bearer\\s+", RegexOption.IGNORE_CASE), "")
        if (token.isBlank()) {
            state = state.copy(message = "请粘贴 Access Token")
            return
        }
        authenticate(token, persist = true)
    }

    fun enterDemo() {
        val collections = demoCollections()
        state = state.copy(
            phase = SessionPhase.SignedIn,
            user = BangumiUser(0, "mubangumi_demo", "MuBangumi", "", "原生 Android 预览模式"),
            collections = collections,
            discover = collections.map { it.subject },
            isDemo = true,
            message = null,
        )
        loadCommunity()
    }

    fun signOut() {
        preferences.edit().remove("access_token").apply()
        state = AppState(phase = SessionPhase.SignedOut, isDarkMode = state.isDarkMode)
    }

    fun refresh() {
        val user = state.user ?: return
        if (state.isDemo) {
            state = state.copy(message = "演示数据已是最新")
            return
        }
        viewModelScope.launch {
            state = state.copy(isRefreshing = true, message = null)
            runCatching { api.getCollections(user.username, state.token) }
                .onSuccess { state = state.copy(collections = it, isRefreshing = false) }
                .onFailure { state = state.copy(isRefreshing = false, message = friendlyMessage(it)) }
        }
    }

    fun loadDiscover(type: SubjectType = SubjectType.Anime) {
        viewModelScope.launch {
            state = state.copy(isDiscoverLoading = true, searchResults = emptyList(), message = null)
            val now = LocalDate.now()
            runCatching {
                api.browseSubjects(
                    type = type,
                    year = if (type == SubjectType.Anime) now.year else null,
                    month = if (type == SubjectType.Anime) ((now.monthValue - 1) / 3) * 3 + 1 else null,
                )
            }.onSuccess {
                state = state.copy(discover = it, isDiscoverLoading = false)
            }.onFailure {
                state = state.copy(isDiscoverLoading = false, message = friendlyMessage(it))
            }
        }
    }

    fun searchSubjects(keyword: String, type: SubjectType) {
        if (keyword.trim().isBlank()) {
            state = state.copy(searchResults = emptyList())
            return
        }
        viewModelScope.launch {
            state = state.copy(isDiscoverLoading = true, message = null)
            runCatching { api.searchSubjects(keyword.trim(), type) }
                .onSuccess { state = state.copy(searchResults = it, isDiscoverLoading = false) }
                .onFailure { state = state.copy(isDiscoverLoading = false, message = friendlyMessage(it)) }
        }
    }

    fun loadCommunity(kind: String = "group") {
        viewModelScope.launch {
            state = state.copy(isCommunityLoading = true, message = null)
            runCatching { api.getTopics(kind) }
                .onSuccess { state = state.copy(topics = it, isCommunityLoading = false) }
                .onFailure { state = state.copy(isCommunityLoading = false, message = friendlyMessage(it)) }
        }
    }

    fun openSubject(subject: Subject) {
        state = state.copy(selectedSubject = subject, isDetailLoading = true, message = null)
        viewModelScope.launch {
            runCatching { api.getSubject(subject.id) }
                .onSuccess { state = state.copy(selectedSubject = it, isDetailLoading = false) }
                .onFailure { state = state.copy(isDetailLoading = false, message = friendlyMessage(it)) }
        }
    }

    fun openTopic(topic: CommunityTopic) {
        state = state.copy(selectedTopic = topic, topicDetail = null, isTopicLoading = true, message = null)
        viewModelScope.launch {
            runCatching { api.getTopicDetail(topic) }
                .onSuccess { state = state.copy(topicDetail = it, isTopicLoading = false) }
                .onFailure { state = state.copy(isTopicLoading = false, message = friendlyMessage(it)) }
        }
    }

    fun closeTopic() {
        state = state.copy(selectedTopic = null, topicDetail = null, isTopicLoading = false)
    }

    fun loadFriends() {
        val user = state.user ?: return
        if (state.isDemo) {
            state = state.copy(friends = demoFriends(), isFriendsLoading = false)
            return
        }
        viewModelScope.launch {
            state = state.copy(isFriendsLoading = true, message = null)
            runCatching { api.getFriends(user.username, state.token) }
                .onSuccess { state = state.copy(friends = it, isFriendsLoading = false) }
                .onFailure { state = state.copy(isFriendsLoading = false, message = friendlyMessage(it)) }
        }
    }

    fun loadNotices() {
        if (state.isDemo) {
            state = state.copy(notices = demoNotices(), isNoticesLoading = false)
            return
        }
        viewModelScope.launch {
            state = state.copy(isNoticesLoading = true, message = null)
            runCatching { api.getNotices(state.token) }
                .onSuccess { state = state.copy(notices = it, isNoticesLoading = false) }
                .onFailure { state = state.copy(isNoticesLoading = false, message = friendlyMessage(it)) }
        }
    }

    fun markNoticesRead() {
        val ids = state.notices.filter { it.unread }.map { it.id }
        if (ids.isEmpty()) return
        state = state.copy(notices = state.notices.map { it.copy(unread = false) })
        if (state.isDemo) return
        viewModelScope.launch {
            runCatching { api.markNoticesRead(state.token, ids) }
                .onFailure { state = state.copy(message = friendlyMessage(it)) }
        }
    }

    fun closeSubject() {
        state = state.copy(selectedSubject = null, isDetailLoading = false)
    }

    fun updateCollection(subject: Subject, status: CollectionStatus) {
        val previous = state.collections.firstOrNull { it.subjectId == subject.id }
        val updated = CollectionItem(
            subjectId = subject.id,
            status = status,
            rate = previous?.rate ?: 0,
            epStatus = previous?.epStatus ?: 0,
            volStatus = previous?.volStatus ?: 0,
            comment = previous?.comment.orEmpty(),
            updatedAt = java.time.Instant.now().toString(),
            subject = subject,
        )
        state = state.copy(
            collections = listOf(updated) + state.collections.filterNot { it.subjectId == subject.id },
            message = "已设为${status.label(subject.type)}",
        )
        if (state.isDemo) return
        viewModelScope.launch {
            runCatching { api.updateCollection(subject.id, status, state.token, previous?.rate ?: 0) }
                .onFailure {
                    val restored = state.collections.filterNot { item -> item.subjectId == subject.id }.toMutableList()
                    if (previous != null) restored.add(0, previous)
                    state = state.copy(collections = restored, message = friendlyMessage(it))
                }
        }
    }

    fun markNextEpisode(item: CollectionItem) {
        if (item.subject.episodeCount > 0 && item.epStatus >= item.subject.episodeCount) {
            state = state.copy(message = "已经全部看完啦")
            return
        }
        val next = item.copy(epStatus = item.epStatus + 1, updatedAt = java.time.Instant.now().toString())
        state = state.copy(
            collections = listOf(next) + state.collections.filterNot { it.subjectId == item.subjectId },
            message = "第 ${next.epStatus} 集已标记为看过",
        )
        if (state.isDemo) return
        viewModelScope.launch {
            runCatching { api.markNextEpisode(item.subjectId, item.epStatus, state.token) }
                .onFailure {
                    state = state.copy(
                        collections = listOf(item) + state.collections.filterNot { it.subjectId == item.subjectId },
                        message = friendlyMessage(it),
                    )
                }
        }
    }

    fun toggleTheme() {
        val dark = !state.isDarkMode
        preferences.edit().putBoolean("dark_mode", dark).apply()
        state = state.copy(isDarkMode = dark)
    }

    fun clearMessage() {
        state = state.copy(message = null)
    }

    private fun authenticate(token: String, persist: Boolean) {
        viewModelScope.launch {
            state = state.copy(phase = SessionPhase.Booting, isRefreshing = true, message = null)
            runCatching {
                val user = api.getMe(token)
                val collections = async { api.getCollections(user.username, token) }.await()
                user to collections
            }.onSuccess { (user, collections) ->
                if (persist) preferences.edit().putString("access_token", token).apply()
                state = state.copy(
                    phase = SessionPhase.SignedIn,
                    user = user,
                    token = token,
                    collections = collections,
                    isRefreshing = false,
                    isDemo = false,
                )
                loadDiscover()
                loadCommunity()
            }.onFailure {
                if (persist) preferences.edit().remove("access_token").apply()
                state = state.copy(
                    phase = SessionPhase.SignedOut,
                    token = "",
                    isRefreshing = false,
                    message = friendlyMessage(it),
                )
            }
        }
    }

    private fun friendlyMessage(error: Throwable): String = when (error) {
        is BangumiApiException -> error.message ?: "Bangumi API 请求失败"
        else -> error.message?.takeIf { it.isNotBlank() } ?: "网络连接失败，请稍后重试"
    }

    private fun demoCollections(): List<CollectionItem> {
        val subjects = listOf(
            Subject(325, SubjectType.Anime, "Kidou Senshi Gundam", "机动战士高达", "https://lain.bgm.tv/pic/cover/l/3e/2f/325_7SrRs.jpg", "人类移居宇宙后的时代，少年阿姆罗意外登上了白色木马。", 43, 0, 8.1, 240, "1979-04-07", 26000, listOf("高达", "SUNRISE", "科幻"), "TV"),
            Subject(265, SubjectType.Anime, "Neon Genesis Evangelion", "新世纪福音战士", "https://lain.bgm.tv/pic/cover/l/44/50/265_3T3QH.jpg", "少年少女与巨大泛用人型决战兵器的故事。", 26, 0, 8.8, 22, "1995-10-04", 70000, listOf("GAINAX", "庵野秀明", "科幻"), "TV"),
            Subject(253, SubjectType.Anime, "Cowboy Bebop", "星际牛仔", "https://lain.bgm.tv/pic/cover/l/9b/3c/253_It6AX.jpg", "在太阳系中追逐赏金、过去与未来。", 26, 0, 9.1, 3, "1998-04-03", 64000, listOf("渡边信一郎", "菅野洋子"), "TV"),
            Subject(978, SubjectType.Anime, "Ghost in the Shell", "攻壳机动队", "https://lain.bgm.tv/pic/cover/l/2f/16/978_0Oq3Q.jpg", "网络与身体边界逐渐消失的未来。", 1, 0, 8.7, 58, "1995-11-18", 27000, listOf("押井守", "赛博朋克"), "剧场版"),
            Subject(8, SubjectType.Book, "Yotsuba&!", "四叶妹妹！", "https://lain.bgm.tv/pic/cover/l/b6/83/8_BQbmR.jpg", "小岩井四叶和邻居们充满惊喜的日常。", 0, 15, 9.0, 8, "2003-03", 33000, listOf("日常", "治愈"), "漫画"),
        )
        val statuses = listOf(CollectionStatus.Doing, CollectionStatus.Doing, CollectionStatus.Done, CollectionStatus.Wish, CollectionStatus.Doing)
        return subjects.mapIndexed { index, subject ->
            CollectionItem(subject.id, statuses[index], if (index == 2) 10 else 0, if (index < 2) index + 5 else 0, 0, "", "2026-08-${15 - index}T12:00:00Z", subject)
        }
    }

    private fun demoFriends() = listOf(
        BangumiUser(2, "sai", "Sai", "", "Awesome!"),
        BangumiUser(10009, "zmsws801", "Mobius", "", ""),
        BangumiUser(928770, "rockleeakq", "Rocklee", "", ""),
    )

    private fun demoNotices() = listOf(
        BangumiNoticeNative(1, "有人回复了你的话题", 1, 1, 3, true, "刚刚", BangumiUser(2, "sai", "Sai", "", "")),
        BangumiNoticeNative(2, "你的好友更新了收藏", 2, 265, 0, false, "昨天 18:20", BangumiUser(10009, "zmsws801", "Mobius", "", "")),
    )
}
