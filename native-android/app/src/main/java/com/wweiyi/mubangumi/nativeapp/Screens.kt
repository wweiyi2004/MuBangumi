@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.wweiyi.mubangumi.nativeapp

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.DoneAll
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.QrCode2
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedAssistChip
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDateTime

@Composable
fun HomeScreen(
    state: AppState,
    onRefresh: () -> Unit,
    onOpen: (Subject) -> Unit,
    onMarkNext: (CollectionItem) -> Unit,
    onSchedule: () -> Unit,
    onDiscover: () -> Unit,
) {
    val watching = state.collections.filter { it.status == CollectionStatus.Doing }
    val hour = LocalDateTime.now().hour
    val greeting = if (hour < 11) "早上好" else if (hour < 18) "下午好" else "晚上好"
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 22.dp, 20.dp, 48.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("$greeting，${state.user?.displayName.orEmpty()}", style = MaterialTheme.typography.headlineMedium)
                    Text("今天也找点喜欢的作品吧", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = onRefresh, enabled = !state.isRefreshing) {
                    if (state.isRefreshing) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else Icon(Icons.Outlined.Refresh, contentDescription = "同步")
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatCard(watching.size.toString(), "进行中", Modifier.weight(1f))
                StatCard(state.collections.count { it.status == CollectionStatus.Done }.toString(), "已完成", Modifier.weight(1f))
                StatCard(state.collections.size.toString(), "总收藏", Modifier.weight(1f))
            }
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    QuickAction(Icons.Outlined.CalendarMonth, "新番表", "安排本季追番", onSchedule, Modifier.weight(1f))
                    QuickAction(Icons.Outlined.Schedule, "每日放送", "官方今日更新", onDiscover, Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    QuickAction(Icons.Outlined.AutoAwesome, "番会荐", "按口味找动画", onDiscover, Modifier.weight(1f))
                    QuickAction(Icons.Outlined.Explore, "找新番", "浏览本季作品", onDiscover, Modifier.weight(1f))
                }
            }
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("继续追", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                Text("${watching.size} 部", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (watching.isEmpty()) {
            item { EmptyCard("还没有进行中的收藏", "去发现页找一部感兴趣的作品吧") }
        } else {
            items(watching.take(18), key = { it.subjectId }) { item ->
                CollectionCard(item, onOpen = { onOpen(item.subject) }, onMarkNext = { onMarkNext(item) })
            }
        }
    }
}

@Composable
private fun StatCard(value: String, label: String, modifier: Modifier = Modifier) {
    Card(modifier = modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(14.dp)) {
            Text(value, fontSize = 23.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun QuickAction(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.padding(14.dp)) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(10.dp))
            Text(title, fontWeight = FontWeight.Bold)
            Text(subtitle, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}

@Composable
private fun EmptyCard(title: String, subtitle: String) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun CollectionCard(item: CollectionItem, onOpen: () -> Unit, onMarkNext: (() -> Unit)? = null) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(Modifier.padding(12.dp)) {
            RemoteImage(
                item.subject.imageUrl,
                item.subject.displayName,
                Modifier.width(78.dp).height(108.dp).clip(RoundedCornerShape(10.dp)),
            )
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(item.subject.displayName, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (item.subject.nameCn.isNotBlank() && item.subject.name.isNotBlank()) {
                    Text(item.subject.name, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Spacer(Modifier.height(7.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(item.status.label(item.subject.type), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    if (item.rate > 0) {
                        Spacer(Modifier.width(8.dp))
                        Icon(Icons.Rounded.Star, null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(15.dp))
                        Text(item.rate.toString(), fontSize = 12.sp)
                    }
                }
                if (item.subject.episodeCount > 0) {
                    Spacer(Modifier.height(9.dp))
                    LinearProgressIndicator(
                        progress = { (item.epStatus.toFloat() / item.subject.episodeCount).coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth().height(5.dp).clip(CircleShape),
                    )
                    Spacer(Modifier.height(5.dp))
                    Text("进度 ${item.epStatus} / ${item.subject.episodeCount}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (onMarkNext != null && item.subject.episodeCount > item.epStatus) {
                FilledIconButton(onClick = onMarkNext, modifier = Modifier.size(38.dp)) {
                    Icon(Icons.Outlined.AddCircle, contentDescription = "下一集看过")
                }
            }
        }
    }
}

@Composable
fun LibraryScreen(state: AppState, onRefresh: () -> Unit, onOpen: (Subject) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var type by rememberSaveable { mutableStateOf<SubjectType?>(SubjectType.Anime) }
    var status by rememberSaveable { mutableStateOf<CollectionStatus?>(CollectionStatus.Doing) }
    val items = state.collections.filter {
        (type == null || it.subject.type == type) &&
            (status == null || it.status == status) &&
            (query.isBlank() || it.subject.displayName.contains(query, true) || it.subject.name.contains(query, true))
    }
    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 22.dp, 20.dp, 48.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("我的收藏", style = MaterialTheme.typography.headlineMedium)
                    Text("找到 ${items.size} 部 · 全部 ${state.collections.size} 部", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = onRefresh) { Icon(Icons.Outlined.Refresh, "同步") }
            }
        }
        item {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("在收藏中搜索") },
                leadingIcon = { Icon(Icons.Outlined.Search, null) },
                trailingIcon = { Icon(Icons.Outlined.Tune, null) },
                singleLine = true,
                shape = AppFieldShape,
            )
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = type == null, onClick = { type = null }, label = { Text("全部类型") })
                SubjectType.entries.forEach { value ->
                    FilterChip(selected = type == value, onClick = { type = value }, label = { Text(value.label) })
                }
            }
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = status == null, onClick = { status = null }, label = { Text("全部状态") })
                CollectionStatus.entries.forEach { value ->
                    FilterChip(selected = status == value, onClick = { status = value }, label = { Text(value.label(type ?: SubjectType.Anime)) })
                }
            }
        }
        if (items.isEmpty()) item { EmptyCard("没有匹配的收藏", "试试更换类型、状态或关键词") }
        items(items, key = { it.subjectId }) { item -> CollectionCard(item, onOpen = { onOpen(item.subject) }) }
    }
    }
}

@Composable
fun DiscoverScreen(
    state: AppState,
    onLoad: (SubjectType) -> Unit,
    onSearch: (String, SubjectType) -> Unit,
    onOpen: (Subject) -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var type by rememberSaveable { mutableStateOf(SubjectType.Anime) }
    val display = if (query.isBlank()) state.discover else state.searchResults
    LaunchedEffect(Unit) { if (state.discover.isEmpty()) onLoad(type) }
    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 22.dp, 20.dp, 48.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
        item {
            Text("发现", style = MaterialTheme.typography.headlineMedium)
            Text("搜索条目，或看看本季口碑作品", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("搜索条目") },
                    leadingIcon = { Icon(Icons.Outlined.Search, null) },
                    singleLine = true,
                    shape = AppFieldShape,
                )
                Spacer(Modifier.width(8.dp))
                Button(onClick = { onSearch(query, type) }, enabled = query.isNotBlank(), modifier = Modifier.height(56.dp)) { Text("搜索") }
            }
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SubjectType.entries.forEach { value ->
                    FilterChip(
                        selected = type == value,
                        onClick = {
                            type = value
                            query = ""
                            onLoad(value)
                        },
                        label = { Text(value.label) },
                    )
                }
            }
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (query.isBlank()) "本季推荐" else "搜索结果", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                Text("${display.size} 部", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (state.isDiscoverLoading) item { Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        if (!state.isDiscoverLoading && display.isEmpty()) item { EmptyCard("暂时没有结果", "换个关键词或条目类型试试") }
        items(display, key = { it.id }) { subject -> SubjectCard(subject, onOpen = { onOpen(subject) }) }
    }
    }
}

@Composable
private fun SubjectCard(subject: Subject, onOpen: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(Modifier.padding(12.dp)) {
            RemoteImage(subject.imageUrl, subject.displayName, Modifier.width(82.dp).height(116.dp).clip(RoundedCornerShape(10.dp)))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(subject.displayName, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (subject.name.isNotBlank()) Text(subject.name, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Star, null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(17.dp))
                    Text(if (subject.score > 0) " ${"%.1f".format(subject.score)}" else " 暂无评分", fontWeight = FontWeight.Bold)
                    if (subject.rank > 0) Text("  #${subject.rank}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                }
                Spacer(Modifier.height(7.dp))
                Text(
                    listOf(subject.date, subject.platform, if (subject.episodeCount > 0) "${subject.episodeCount} 话" else "").filter { it.isNotBlank() }.joinToString(" · "),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(7.dp))
                Text(subject.summary.ifBlank { "暂无简介" }, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 13.sp)
            }
            Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.outline)
        }
    }
}

@Composable
fun CommunityScreen(state: AppState, onLoad: (String) -> Unit, onOpen: (CommunityTopic) -> Unit) {
    var kind by rememberSaveable { mutableStateOf("group") }
    LaunchedEffect(Unit) { if (state.topics.isEmpty()) onLoad(kind) }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 22.dp, 20.dp, 48.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("社区", style = MaterialTheme.typography.headlineMedium)
                    Text("原生浏览超展开与最新话题", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = { onLoad(kind) }) { Icon(Icons.Outlined.Refresh, "刷新") }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = kind == "group", onClick = { kind = "group"; onLoad(kind) }, label = { Text("小组") }, leadingIcon = { Icon(Icons.Outlined.Groups, null, Modifier.size(18.dp)) })
                FilterChip(selected = kind == "subject", onClick = { kind = "subject"; onLoad(kind) }, label = { Text("条目") }, leadingIcon = { Icon(Icons.Outlined.Forum, null, Modifier.size(18.dp)) })
            }
        }
        if (state.isCommunityLoading) item { Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        if (!state.isCommunityLoading && state.topics.isEmpty()) item { EmptyCard("社区暂时无法加载", "可以稍后刷新，或检查网络连接") }
        items(state.topics, key = { "${it.kind}-${it.id}" }) { topic ->
            Card(
                modifier = Modifier.fillMaxWidth().clickable { onOpen(topic) },
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            ) {
                Row(Modifier.padding(14.dp)) {
                    if (topic.avatarUrl.isNotBlank()) {
                        RemoteImage(topic.avatarUrl, topic.author, Modifier.size(42.dp).clip(CircleShape))
                    } else {
                        Box(Modifier.size(42.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                            Icon(Icons.Outlined.Person, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(topic.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(5.dp))
                        Text(listOf(topic.sourceTitle, topic.author).filter { it.isNotBlank() }.joinToString(" · "), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("${topic.replyCount} 回复 · ${topic.updatedAt}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.outline)
                }
            }
        }
    }
}

@Composable
fun ProfileScreen(
    state: AppState,
    onToggleTheme: () -> Unit,
    onSignOut: () -> Unit,
    onFriends: () -> Unit,
    onNotices: () -> Unit,
) {
    val user = state.user ?: return
    var showAbout by rememberSaveable { mutableStateOf(false) }
    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 22.dp, 20.dp, 48.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
        item { Text("我的", style = MaterialTheme.typography.headlineMedium) }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Row(Modifier.fillMaxWidth().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (user.avatarUrl.isNotBlank()) RemoteImage(user.avatarUrl, user.displayName, Modifier.size(76.dp).clip(CircleShape))
                    else Box(Modifier.size(76.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { Text(user.displayName.take(1).uppercase(), style = MaterialTheme.typography.headlineMedium) }
                    Spacer(Modifier.width(18.dp))
                    Column(Modifier.weight(1f)) {
                        Text(user.displayName, style = MaterialTheme.typography.titleLarge)
                        Text("@${user.username}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (user.sign.isNotBlank()) { Spacer(Modifier.height(6.dp)); Text(user.sign, maxLines = 3, overflow = TextOverflow.Ellipsis) }
                    }
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatCard(state.collections.count { it.status == CollectionStatus.Doing }.toString(), "进行中", Modifier.weight(1f))
                StatCard(state.collections.count { it.status == CollectionStatus.Done }.toString(), "已完成", Modifier.weight(1f))
                StatCard(state.collections.size.toString(), "总收藏", Modifier.weight(1f))
            }
        }
        item { SectionTitle("社交") }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                ProfileAction(Icons.Outlined.Groups, "我的好友", "查看好友与公开收藏", onFriends)
                HorizontalDivider(Modifier.padding(start = 56.dp))
                ProfileAction(Icons.Outlined.Notifications, "电波提醒", "原生通知列表", onNotices)
                HorizontalDivider(Modifier.padding(start = 56.dp))
                ProfileAction(Icons.Outlined.Person, "我的账号", "${user.username} · ${user.id}") {}
            }
        }
        item { SectionTitle("偏好与数据") }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (state.isDarkMode) Icons.Outlined.DarkMode else Icons.Outlined.LightMode, null)
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) { Text("深色模式", fontWeight = FontWeight.Medium); Text("跟随你的阅读环境", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Switch(checked = state.isDarkMode, onCheckedChange = { onToggleTheme() })
                }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                ProfileAction(Icons.Outlined.Language, "关于 MuBangumi", "原生 Android · Bangumi API") { showAbout = true }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                ProfileAction(Icons.Outlined.Settings, "数据与隐私", "Access Token 只用于 Bangumi API") {}
            }
        }
        item {
            OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth().height(48.dp), shape = AppFieldShape) { Text(if (state.isDemo) "退出预览" else "退出登录") }
        }
        }
        if (showAbout) {
            AlertDialog(
                onDismissRequest = { showAbout = false },
                title = { Text("MuBangumi") },
                text = { Text("原生 Android 客户端\nKotlin + Jetpack Compose\n数据来自 Bangumi OpenAPI 与 P1。") },
                confirmButton = { androidx.compose.material3.TextButton(onClick = { showAbout = false }) { Text("知道了") } },
            )
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 6.dp))
}

@Composable
private fun ProfileAction(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) { Text(title, fontWeight = FontWeight.Medium); Text(subtitle, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.outline)
    }
}

@Composable
fun SubjectDetailScreen(
    subject: Subject,
    collection: CollectionItem?,
    loading: Boolean,
    onBack: () -> Unit,
    onStatusChange: (CollectionStatus) -> Unit,
    onMarkNext: (CollectionItem) -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("条目详情", maxLines = 1) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回") } },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(20.dp),
        ) {
            Row {
                RemoteImage(subject.imageUrl, subject.displayName, Modifier.width(124.dp).aspectRatio(0.7f).clip(RoundedCornerShape(14.dp)), ContentScale.Crop)
                Spacer(Modifier.width(18.dp))
                Column(Modifier.weight(1f)) {
                    Text(subject.displayName, style = MaterialTheme.typography.headlineMedium)
                    if (subject.name.isNotBlank()) Text(subject.name, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Star, null, tint = MaterialTheme.colorScheme.tertiary)
                        Spacer(Modifier.width(5.dp))
                        Text(if (subject.score > 0) "${"%.1f".format(subject.score)}" else "暂无", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                    if (subject.rank > 0) Text("Bangumi 排名 #${subject.rank}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(10.dp))
                    Text(listOf(subject.date, subject.platform).filter { it.isNotBlank() }.joinToString(" · "), fontSize = 13.sp)
                    if (subject.episodeCount > 0) Text("全 ${subject.episodeCount} 话", fontSize = 13.sp)
                }
            }
            if (loading) { Spacer(Modifier.height(14.dp)); LinearProgressIndicator(Modifier.fillMaxWidth()) }
            Spacer(Modifier.height(22.dp))
            Text("收藏状态", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CollectionStatus.entries.forEach { status ->
                    FilterChip(
                        selected = collection?.status == status,
                        onClick = { onStatusChange(status) },
                        label = { Text(status.label(subject.type)) },
                        leadingIcon = if (collection?.status == status) ({ Icon(Icons.Rounded.CheckCircle, null, Modifier.size(17.dp)) }) else null,
                    )
                }
            }
            if (collection != null && subject.episodeCount > 0) {
                Spacer(Modifier.height(18.dp))
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                    Column(Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("观看进度", fontWeight = FontWeight.Bold)
                                Text("${collection.epStatus} / ${subject.episodeCount} 话", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Button(onClick = { onMarkNext(collection) }, enabled = collection.epStatus < subject.episodeCount) {
                                Icon(Icons.Outlined.DoneAll, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("下一集看过")
                            }
                        }
                        Spacer(Modifier.height(10.dp))
                        LinearProgressIndicator(progress = { (collection.epStatus.toFloat() / subject.episodeCount).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().height(6.dp).clip(CircleShape))
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            Text("简介", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(8.dp))
            Text(subject.summary.ifBlank { "暂无简介" }, style = MaterialTheme.typography.bodyLarge)
            if (subject.tags.isNotEmpty()) {
                Spacer(Modifier.height(22.dp))
                Text("标签", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(8.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    subject.tags.forEach { tag -> AssistChip(onClick = {}, label = { Text(tag) }, leadingIcon = { Icon(Icons.Outlined.Tag, null, Modifier.size(16.dp)) }) }
                }
            }
            Spacer(Modifier.height(40.dp))
        }
    }
}

@Composable
fun ScheduleScreen(collections: List<CollectionItem>, onBack: () -> Unit, onOpen: (Subject) -> Unit) {
    val days = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    var selectedDay by rememberSaveable { mutableStateOf((java.time.LocalDate.now().dayOfWeek.value - 1).coerceIn(0, 6)) }
    val watching = collections.filter { it.status == CollectionStatus.Doing && it.subject.type == SubjectType.Anime }
    val today = watching.filter { it.subjectId.mod(7) == selectedDay }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { TopAppBar(title = { Text("新番表") }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回") } }) },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 12.dp, 20.dp, 40.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text("我的本季追番", style = MaterialTheme.typography.headlineMedium)
                Text("按周查看进行中的动画", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            item {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    days.forEachIndexed { index, day -> FilterChip(selected = selectedDay == index, onClick = { selectedDay = index }, label = { Text(day) }) }
                }
            }
            item { Text("${days[selectedDay]} · ${today.size} 部", style = MaterialTheme.typography.titleLarge) }
            if (today.isEmpty()) item { EmptyCard("今天没有安排", "进行中的动画会自动出现在本地新番表") }
            items(today, key = { it.subjectId }) { item -> CollectionCard(item, onOpen = { onOpen(item.subject) }) }
        }
    }
}

@Composable
fun TopicDetailScreen(
    topic: CommunityTopic,
    detail: CommunityTopicDetail?,
    loading: Boolean,
    onBack: () -> Unit,
) {
    val title = detail?.title ?: topic.title
    val sourceTitle = detail?.sourceTitle ?: topic.sourceTitle
    val posts = detail?.posts.orEmpty()
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("话题详情", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回") } },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 14.dp, 20.dp, 44.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(title, style = MaterialTheme.typography.headlineSmall)
                if (sourceTitle.isNotBlank()) {
                    Spacer(Modifier.height(5.dp))
                    Text(sourceTitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.height(4.dp))
                Text("${topic.author} · ${topic.replyCount} 回复 · ${topic.updatedAt}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (loading) {
                item { Box(Modifier.fillMaxWidth().padding(28.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
            } else if (posts.isEmpty()) {
                item { EmptyCard("暂无可见回复", "这个话题可能已被删除，或暂时没有公开回复") }
            }
            items(posts) { post ->
                Card(
                    modifier = Modifier.fillMaxWidth().padding(start = if (post.nested) 18.dp else 0.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
                        if (post.avatarUrl.isNotBlank()) {
                            RemoteImage(post.avatarUrl, post.author, Modifier.size(38.dp).clip(CircleShape))
                        } else {
                            Box(Modifier.size(38.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                                Icon(Icons.Outlined.Person, null, tint = MaterialTheme.colorScheme.primary)
                            }
                        }
                        Spacer(Modifier.width(11.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(post.author.ifBlank { "匿名用户" }, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                                Text(post.createdAt, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(Modifier.height(7.dp))
                            Text(post.content, lineHeight = 21.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun FriendsScreen(
    friends: List<BangumiUser>,
    loading: Boolean,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("我的好友") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回") } },
                actions = {
                    IconButton(onClick = onRefresh, enabled = !loading) {
                        if (loading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Icon(Icons.Outlined.Refresh, "刷新")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 14.dp, 20.dp, 44.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Text("${friends.size} 位好友", style = MaterialTheme.typography.headlineSmall)
                Text("来自 Bangumi 的公开好友列表", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (loading && friends.isEmpty()) {
                item { Box(Modifier.fillMaxWidth().padding(28.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
            } else if (!loading && friends.isEmpty()) {
                item { EmptyCard("还没有好友", "在 Bangumi 添加好友后会显示在这里") }
            }
            items(friends, key = { it.id }) { friend ->
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (friend.avatarUrl.isNotBlank()) {
                            RemoteImage(friend.avatarUrl, friend.displayName, Modifier.size(50.dp).clip(CircleShape))
                        } else {
                            Box(Modifier.size(50.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                                Text(friend.displayName.take(1).uppercase(), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                            }
                        }
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(friend.displayName, style = MaterialTheme.typography.titleMedium)
                            Text("@${friend.username}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (friend.sign.isNotBlank()) Text(friend.sign, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun NoticesScreen(
    notices: List<BangumiNoticeNative>,
    loading: Boolean,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onMarkRead: () -> Unit,
) {
    val unreadCount = notices.count { it.unread }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("电波提醒") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回") } },
                actions = {
                    IconButton(onClick = onRefresh, enabled = !loading) {
                        if (loading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Icon(Icons.Outlined.Refresh, "刷新")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp, 14.dp, 20.dp, 44.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("${notices.size} 条提醒", style = MaterialTheme.typography.headlineSmall)
                        Text(if (unreadCount == 0) "全部已读" else "$unreadCount 条未读", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (unreadCount > 0) {
                        OutlinedButton(onClick = onMarkRead) { Icon(Icons.Outlined.DoneAll, null, Modifier.size(17.dp)); Spacer(Modifier.width(5.dp)); Text("全部已读") }
                    }
                }
            }
            if (loading && notices.isEmpty()) {
                item { Box(Modifier.fillMaxWidth().padding(28.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
            } else if (!loading && notices.isEmpty()) {
                item { EmptyCard("暂时没有提醒", "新的回复和动态会出现在这里") }
            }
            items(notices, key = { it.id }) { notice ->
                Card(
                    colors = CardDefaults.cardColors(containerColor = if (notice.unread) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f) else MaterialTheme.colorScheme.surface),
                ) {
                    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.Top) {
                        val sender = notice.sender
                        if (sender?.avatarUrl.orEmpty().isNotBlank()) {
                            RemoteImage(sender!!.avatarUrl, sender.displayName, Modifier.size(42.dp).clip(CircleShape))
                        } else {
                            Box(Modifier.size(42.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                                Icon(Icons.Outlined.Notifications, null, tint = MaterialTheme.colorScheme.primary)
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(notice.title, fontWeight = if (notice.unread) FontWeight.Bold else FontWeight.Medium, modifier = Modifier.weight(1f))
                                Text(notice.createdAt, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (sender != null) Text("来自 ${sender.displayName}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (notice.unread) {
                            Spacer(Modifier.width(8.dp))
                            Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary))
                        }
                    }
                }
            }
        }
    }
}
