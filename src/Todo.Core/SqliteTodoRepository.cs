using System.Globalization;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using Todo.Core.Models;

namespace Todo.Core;

public sealed class SqliteTodoRepository : ITodoRepository
{
    private readonly string _connectionString;
    private readonly IClock _clock;

    public SqliteTodoRepository(string databasePath, IClock clock)
    {
        _clock = clock;

        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        _connectionString = new SqliteConnectionStringBuilder { DataSource = databasePath }.ToString();
        EnsureSchema();
    }

    private void EnsureSchema()
    {
        using var connection = OpenConnection();
        using var command = connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE IF NOT EXISTS todos (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                notes TEXT,
                is_done INTEGER NOT NULL DEFAULT 0,
                due_at TEXT,
                recurrence TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                is_deleted INTEGER NOT NULL DEFAULT 0,
                dirty INTEGER NOT NULL DEFAULT 0,
                server_seq INTEGER
            );
            """;
        command.ExecuteNonQuery();
    }

    private SqliteConnection OpenConnection()
    {
        var connection = new SqliteConnection(_connectionString);
        connection.Open();
        return connection;
    }

    public async Task<Result<IReadOnlyList<TodoItem>>> GetActiveAsync(CancellationToken ct = default)
    {
        try
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = """
                SELECT id, title, notes, is_done, due_at, recurrence, created_at, updated_at, is_deleted, dirty, server_seq
                FROM todos
                WHERE is_deleted = 0
                ORDER BY due_at IS NULL, due_at ASC, created_at ASC;
                """;

            var items = new List<TodoItem>();
            using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                items.Add(ReadItem(reader));
            }

            return Result.Ok<IReadOnlyList<TodoItem>>(items);
        }
        catch (Exception ex)
        {
            return Result.Fail<IReadOnlyList<TodoItem>>($"Failed to load todos: {ex.Message}");
        }
    }

    public async Task<Result<TodoItem>> AddAsync(TodoItem item, CancellationToken ct = default)
    {
        try
        {
            item.UpdatedAt = _clock.UtcNow;
            item.Dirty = true;

            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO todos (id, title, notes, is_done, due_at, recurrence, created_at, updated_at, is_deleted, dirty, server_seq)
                VALUES (@id, @title, @notes, @is_done, @due_at, @recurrence, @created_at, @updated_at, @is_deleted, @dirty, @server_seq);
                """;
            BindParameters(command, item);
            await command.ExecuteNonQueryAsync(ct);

            return Result.Ok(item);
        }
        catch (Exception ex)
        {
            return Result.Fail<TodoItem>($"Failed to add todo: {ex.Message}");
        }
    }

    public async Task<Result<TodoItem>> UpdateAsync(TodoItem item, CancellationToken ct = default)
    {
        try
        {
            item.UpdatedAt = _clock.UtcNow;
            item.Dirty = true;

            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = """
                UPDATE todos
                SET title = @title, notes = @notes, is_done = @is_done, due_at = @due_at,
                    recurrence = @recurrence, updated_at = @updated_at, is_deleted = @is_deleted,
                    dirty = @dirty, server_seq = @server_seq
                WHERE id = @id;
                """;
            BindParameters(command, item);
            var rowsAffected = await command.ExecuteNonQueryAsync(ct);

            return rowsAffected == 0
                ? Result.Fail<TodoItem>($"No todo found with id {item.Id}.")
                : Result.Ok(item);
        }
        catch (Exception ex)
        {
            return Result.Fail<TodoItem>($"Failed to update todo: {ex.Message}");
        }
    }

    public async Task<Result> DeleteAsync(Guid id, CancellationToken ct = default)
    {
        try
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = """
                UPDATE todos SET is_deleted = 1, updated_at = @updated_at, dirty = 1 WHERE id = @id;
                """;
            command.Parameters.AddWithValue("@updated_at", ToIso8601(_clock.UtcNow));
            command.Parameters.AddWithValue("@id", id.ToString());
            var rowsAffected = await command.ExecuteNonQueryAsync(ct);

            return rowsAffected == 0
                ? Result.Fail($"No todo found with id {id}.")
                : Result.Ok();
        }
        catch (Exception ex)
        {
            return Result.Fail($"Failed to delete todo: {ex.Message}");
        }
    }

    private static void BindParameters(SqliteCommand command, TodoItem item)
    {
        command.Parameters.AddWithValue("@id", item.Id.ToString());
        command.Parameters.AddWithValue("@title", item.Title);
        command.Parameters.AddWithValue("@notes", (object?)item.Notes ?? DBNull.Value);
        command.Parameters.AddWithValue("@is_done", item.IsDone ? 1 : 0);
        command.Parameters.AddWithValue("@due_at", item.DueAt is { } dueAt ? ToIso8601(dueAt) : DBNull.Value);
        command.Parameters.AddWithValue("@recurrence", item.Recurrence is { } recurrence
            ? JsonSerializer.Serialize(recurrence)
            : DBNull.Value);
        command.Parameters.AddWithValue("@created_at", ToIso8601(item.CreatedAt));
        command.Parameters.AddWithValue("@updated_at", ToIso8601(item.UpdatedAt));
        command.Parameters.AddWithValue("@is_deleted", item.IsDeleted ? 1 : 0);
        command.Parameters.AddWithValue("@dirty", item.Dirty ? 1 : 0);
        command.Parameters.AddWithValue("@server_seq", (object?)item.ServerSeq ?? DBNull.Value);
    }

    private static TodoItem ReadItem(SqliteDataReader reader)
    {
        return new TodoItem
        {
            Id = Guid.Parse(reader.GetString(0)),
            Title = reader.GetString(1),
            Notes = reader.IsDBNull(2) ? null : reader.GetString(2),
            IsDone = reader.GetInt64(3) != 0,
            DueAt = reader.IsDBNull(4) ? null : ParseIso8601(reader.GetString(4)),
            Recurrence = reader.IsDBNull(5) ? null : JsonSerializer.Deserialize<RecurrenceRule>(reader.GetString(5)),
            CreatedAt = ParseIso8601(reader.GetString(6)),
            UpdatedAt = ParseIso8601(reader.GetString(7)),
            IsDeleted = reader.GetInt64(8) != 0,
            Dirty = reader.GetInt64(9) != 0,
            ServerSeq = reader.IsDBNull(10) ? null : reader.GetInt64(10),
        };
    }

    private static string ToIso8601(DateTimeOffset value) => value.ToString("O", CultureInfo.InvariantCulture);

    private static DateTimeOffset ParseIso8601(string value) => DateTimeOffset.Parse(value, CultureInfo.InvariantCulture);
}
