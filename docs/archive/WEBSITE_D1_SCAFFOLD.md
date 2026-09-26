# 已归档的网站 D1 示例

这些模板文件未被 MuBangumi 主页引用，原站点未配置 D1。2026-09-22 维护时从活动工程移除，保留内容供未来独立数据库功能参考；当前网站不安装 Drizzle 依赖。

## website/db/index.ts

```
import { env } from "cloudflare:workers";
import { drizzle } from "drizzle-orm/d1";
import * as schema from "./schema";

export function getDb() {
  if (!env.DB) {
    throw new Error(
      "Cloudflare D1 binding `DB` is unavailable. Set the `d1` field in .openai/hosting.json to `DB` or let your control plane inject the real binding values before using the database."
    );
  }

  return drizzle(env.DB, { schema });
}

```

## website/db/schema.ts

```
// Intentionally empty by default.
// Add Drizzle tables here when the site actually needs a database.
// See examples/d1/db/schema.ts for an opt-in example.
export {};

```

## website/drizzle.config.ts

```
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  out: "./drizzle",
  schema: "./db/schema.ts",
  dialect: "sqlite",
});

```

## website/examples/d1/db/schema.ts

```
import { sql } from "drizzle-orm";
import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const notes = sqliteTable("notes", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  title: text("title").notNull(),
  content: text("content").notNull().default(""),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});

```

## website/examples/d1/app/api/notes/route.ts

```
import { desc } from "drizzle-orm";
import { getDb } from "../../../../../db";
import { notes } from "../../../db/schema";

function toRouteErrorMessage(error: unknown) {
  const message = error instanceof Error ? error.message : "Unexpected error";
  const detail =
    error instanceof Error && error.cause instanceof Error ? error.cause.message : "";
  const combined = `${message}\n${detail}`;

  if (combined.includes("no such table") || combined.includes('from "notes"')) {
    return "The notes table is unavailable. Generate the migration locally with `npm run db:generate`, then deploy so the platform can apply the generated SQL to the real D1 database.";
  }

  return message;
}

export async function GET() {
  try {
    const db = getDb();
    const rows = await db
      .select()
      .from(notes)
      .orderBy(desc(notes.createdAt), desc(notes.id))
      .limit(20);

    return Response.json({ notes: rows });
  } catch (error) {
    return Response.json(
      { error: toRouteErrorMessage(error) },
      { status: 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const payload = (await request.json()) as {
      title?: string;
      content?: string;
    };
    const title = payload.title?.trim() ?? "";
    const content = payload.content?.trim() ?? "";

    if (!title) {
      return Response.json({ error: "title is required" }, { status: 400 });
    }

    const db = getDb();
    const [note] = await db.insert(notes).values({ title, content }).returning();
    return Response.json({ note }, { status: 201 });
  } catch (error) {
    return Response.json(
      { error: toRouteErrorMessage(error) },
      { status: 500 }
    );
  }
}

```

## website/drizzle/meta/_journal.json

```
{
  "version": "7",
  "dialect": "sqlite",
  "entries": []
}

```
