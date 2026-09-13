namespace Todo.Core;

/// <summary>
/// Orchestrates one sync cycle: push all dirty rows, clear Dirty for the ones the Worker
/// applied, then pull changes since the last cursor (looping until drained), applying and
/// persisting the cursor as it goes. Matches project-plan.md's protocol description exactly.
/// </summary>
public sealed class SyncEngine
{
    private readonly ITodoRepository _repository;
    private readonly ISyncClient _syncClient;

    public SyncEngine(ITodoRepository repository, ISyncClient syncClient)
    {
        _repository = repository;
        _syncClient = syncClient;
    }

    public async Task<Result> SyncAsync(CancellationToken ct = default)
    {
        var pushResult = await PushDirtyAsync(ct);
        if (!pushResult.IsSuccess)
        {
            return pushResult;
        }

        return await PullChangesAsync(ct);
    }

    private async Task<Result> PushDirtyAsync(CancellationToken ct)
    {
        var dirtyResult = await _repository.GetDirtyAsync(ct);
        if (!dirtyResult.IsSuccess)
        {
            return Result.Fail(dirtyResult.Error!);
        }

        if (dirtyResult.Value.Count == 0)
        {
            return Result.Ok();
        }

        var pushResult = await _syncClient.PushAsync(dirtyResult.Value, ct);
        if (!pushResult.IsSuccess)
        {
            return Result.Fail(pushResult.Error!);
        }

        var appliedIds = pushResult.Value.Applied.Select(a => a.Id).ToList();
        return await _repository.ClearDirtyAsync(appliedIds, ct);
    }

    private async Task<Result> PullChangesAsync(CancellationToken ct)
    {
        var cursorResult = await _repository.GetSyncCursorAsync(ct);
        if (!cursorResult.IsSuccess)
        {
            return Result.Fail(cursorResult.Error!);
        }

        var cursor = cursorResult.Value;

        while (true)
        {
            var changesResult = await _syncClient.GetChangesAsync(cursor, ct);
            if (!changesResult.IsSuccess)
            {
                return Result.Fail(changesResult.Error!);
            }

            var changes = changesResult.Value;
            foreach (var item in changes.Items)
            {
                var applyResult = await _repository.ApplyRemoteAsync(item, ct);
                if (!applyResult.IsSuccess)
                {
                    return Result.Fail(applyResult.Error!);
                }
            }

            var setCursorResult = await _repository.SetSyncCursorAsync(changes.Cursor, ct);
            if (!setCursorResult.IsSuccess)
            {
                return Result.Fail(setCursorResult.Error!);
            }

            if (changes.Items.Count == 0 || changes.Cursor == cursor)
            {
                return Result.Ok();
            }

            cursor = changes.Cursor;
        }
    }
}
