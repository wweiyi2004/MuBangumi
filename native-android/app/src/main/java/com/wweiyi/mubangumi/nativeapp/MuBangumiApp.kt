package com.wweiyi.mubangumi.nativeapp

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircle
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

private data class MainDestination(
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector,
)

private val mainDestinations = listOf(
    MainDestination("追番", Icons.Outlined.PlayCircle, Icons.Rounded.PlayCircle),
    MainDestination("收藏", Icons.Outlined.VideoLibrary, Icons.Rounded.VideoLibrary),
    MainDestination("发现", Icons.Outlined.Explore, Icons.Rounded.Explore),
    MainDestination("社区", Icons.Outlined.Forum, Icons.Rounded.Forum),
    MainDestination("我的", Icons.Outlined.Person, Icons.Rounded.Person),
)

@Composable
fun MuBangumiApp(viewModel: MuBangumiViewModel) {
    val state = viewModel.state
    MuBangumiTheme(darkMode = state.isDarkMode) {
        when (state.phase) {
            SessionPhase.Booting -> LaunchScreen()
            SessionPhase.SignedOut -> AuthScreen(
                loading = state.isRefreshing,
                message = state.message,
                onSignIn = viewModel::signIn,
                onDemo = viewModel::enterDemo,
            )
            SessionPhase.SignedIn -> {
                if (state.selectedTopic != null) {
                    TopicDetailScreen(
                        topic = state.selectedTopic,
                        detail = state.topicDetail,
                        loading = state.isTopicLoading,
                        onBack = viewModel::closeTopic,
                    )
                    BackHandler(onBack = viewModel::closeTopic)
                } else if (state.selectedSubject != null) {
                    SubjectDetailScreen(
                        subject = state.selectedSubject,
                        collection = state.collections.firstOrNull { it.subjectId == state.selectedSubject.id },
                        loading = state.isDetailLoading,
                        onBack = viewModel::closeSubject,
                        onStatusChange = { viewModel.updateCollection(state.selectedSubject, it) },
                        onMarkNext = viewModel::markNextEpisode,
                    )
                    BackHandler(onBack = viewModel::closeSubject)
                } else {
                    MainShell(viewModel)
                }
            }
        }
    }
}

@Composable
private fun LaunchScreen() {
    Box(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            BrandMark(76)
            Spacer(Modifier.height(22.dp))
            Text("MuBangumi", style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(28.dp))
            CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.5.dp)
        }
    }
}

@Composable
fun BrandMark(size: Int = 52) {
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(RoundedCornerShape((size * 0.3f).dp))
            .background(
                Brush.linearGradient(listOf(Color(0xFFFF779D), Color(0xFFE7447A))),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Rounded.PlayArrow,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size((size * 0.64f).dp),
        )
    }
}

@Composable
private fun AuthScreen(
    loading: Boolean,
    message: String?,
    onSignIn: (String) -> Unit,
    onDemo: () -> Unit,
) {
    var token by rememberSaveable { mutableStateOf("") }
    val context = LocalContext.current
    Box(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BrandMark(72)
            Spacer(Modifier.height(20.dp))
            Text("欢迎使用 MuBangumi", style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(8.dp))
            Text(
                "把 Bangumi 收藏带到原生 Android",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(30.dp))
            OutlinedTextField(
                value = token,
                onValueChange = { token = it },
                modifier = Modifier.fillMaxWidth(),
                enabled = !loading,
                label = { Text("Bangumi Access Token") },
                placeholder = { Text("粘贴个人访问令牌") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                shape = AppFieldShape,
            )
            if (!message.isNullOrBlank()) {
                Spacer(Modifier.height(10.dp))
                Text(message, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
            }
            Spacer(Modifier.height(18.dp))
            Button(
                onClick = { onSignIn(token) },
                enabled = !loading,
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = AppFieldShape,
            ) {
                if (loading) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text("登录并同步收藏", fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(10.dp))
            OutlinedButton(
                onClick = onDemo,
                enabled = !loading,
                modifier = Modifier.fillMaxWidth().height(48.dp),
                shape = AppFieldShape,
            ) {
                Text("先看看界面")
            }
            Spacer(Modifier.height(14.dp))
            Text(
                "获取个人令牌",
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(8.dp),
                fontWeight = FontWeight.SemiBold,
            )
            OutlinedButton(
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://next.bgm.tv/demo/access-token")))
                },
                shape = RoundedCornerShape(12.dp),
            ) {
                Text("在浏览器中打开 Bangumi")
            }
        }
    }
}

@Composable
private fun MainShell(viewModel: MuBangumiViewModel) {
    val state = viewModel.state
    var selectedIndex by rememberSaveable { mutableIntStateOf(0) }
    var showSchedule by rememberSaveable { mutableStateOf(false) }
    var profileSubPage by rememberSaveable { mutableStateOf("") }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.message) {
        val message = state.message ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        delay(100)
        viewModel.clearMessage()
    }

    if (showSchedule) {
        ScheduleScreen(collections = state.collections, onBack = { showSchedule = false }, onOpen = viewModel::openSubject)
        BackHandler { showSchedule = false }
        return
    }

    if (profileSubPage == "friends") {
        FriendsScreen(state.friends, state.isFriendsLoading, onBack = { profileSubPage = "" }, onRefresh = viewModel::loadFriends)
        BackHandler { profileSubPage = "" }
        return
    }
    if (profileSubPage == "notices") {
        NoticesScreen(state.notices, state.isNoticesLoading, onBack = { profileSubPage = "" }, onRefresh = viewModel::loadNotices, onMarkRead = viewModel::markNoticesRead)
        BackHandler { profileSubPage = "" }
        return
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                mainDestinations.forEachIndexed { index, destination ->
                    NavigationBarItem(
                        selected = selectedIndex == index,
                        onClick = { selectedIndex = index },
                        icon = {
                            Icon(
                                if (selectedIndex == index) destination.selectedIcon else destination.icon,
                                contentDescription = destination.label,
                            )
                        },
                        label = { Text(destination.label, fontSize = 11.sp) },
                    )
                }
            }
        },
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
            when (selectedIndex) {
                0 -> HomeScreen(
                    state = state,
                    onRefresh = viewModel::refresh,
                    onOpen = viewModel::openSubject,
                    onMarkNext = viewModel::markNextEpisode,
                    onSchedule = { showSchedule = true },
                    onDiscover = { selectedIndex = 2 },
                )
                1 -> LibraryScreen(state = state, onRefresh = viewModel::refresh, onOpen = viewModel::openSubject)
                2 -> DiscoverScreen(
                    state = state,
                    onLoad = viewModel::loadDiscover,
                    onSearch = viewModel::searchSubjects,
                    onOpen = viewModel::openSubject,
                )
                3 -> CommunityScreen(state = state, onLoad = viewModel::loadCommunity, onOpen = viewModel::openTopic)
                4 -> ProfileScreen(
                    state = state,
                    onToggleTheme = viewModel::toggleTheme,
                    onSignOut = viewModel::signOut,
                    onFriends = { profileSubPage = "friends"; viewModel.loadFriends() },
                    onNotices = { profileSubPage = "notices"; viewModel.loadNotices() },
                )
            }
        }
    }
}
