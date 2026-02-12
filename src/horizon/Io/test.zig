//! std.Io tests ~yoinked~ imported from std (as we can't test it directly)

test "random" {
    const io = testing.io;

    var a: u64 = undefined;
    var b: u64 = undefined;
    var c: u64 = undefined;

    io.random(@ptrCast(&a));
    io.random(@ptrCast(&b));
    io.random(@ptrCast(&c));

    try std.testing.expect(a ^ b ^ c != 0);
}

fn testQueue(comptime len: usize) !void {
    const io = testing.io;
    var buf: [len]usize = undefined;
    var queue: Io.Queue(usize) = .init(&buf);
    var begin: usize = 0;
    for (1..len + 1) |n| {
        const end = begin + n;
        for (begin..end) |i| try queue.putOne(io, i);
        for (begin..end) |i| try expect(try queue.getOne(io) == i);
        begin = end;
    }
}

test "Queue" {
    try testQueue(1);
    try testQueue(2);
    try testQueue(3);
    try testQueue(4);
    try testQueue(5);
}

test "Queue.close single-threaded" {
    const io = std.testing.io;

    var buf: [10]u8 = undefined;
    var queue: Io.Queue(u8) = .init(&buf);

    try queue.putAll(io, &.{ 0, 1, 2, 3, 4, 5, 6 });
    try expectEqual(3, try queue.put(io, &.{ 7, 8, 9, 10 }, 0)); // there is capacity for 3 more items

    var get_buf: [4]u8 = undefined;

    // Receive some elements before closing
    try expectEqual(4, try queue.get(io, &get_buf, 0));
    try expectEqual(0, get_buf[0]);
    try expectEqual(1, get_buf[1]);
    try expectEqual(2, get_buf[2]);
    try expectEqual(3, get_buf[3]);
    try expectEqual(4, try queue.getOne(io));

    // ...and add a couple more now there's space
    try queue.putAll(io, &.{ 20, 21 });

    queue.close(io);

    // Receive more elements *after* closing
    try expectEqual(4, try queue.get(io, &get_buf, 0));
    try expectEqual(5, get_buf[0]);
    try expectEqual(6, get_buf[1]);
    try expectEqual(7, get_buf[2]);
    try expectEqual(8, get_buf[3]);
    try expectEqual(9, try queue.getOne(io));

    // Cannot put anything while closed, even if the buffer has space
    try expectError(error.Closed, queue.putOne(io, 100));
    try expectError(error.Closed, queue.putAll(io, &.{ 101, 102 }));
    try expectError(error.Closed, queue.putUncancelable(io, &.{ 103, 104 }, 0));

    // Even if we ask for 3 items, the queue is closed, so we only get the last 2
    try expectEqual(2, try queue.get(io, &get_buf, 4));
    try expectEqual(20, get_buf[0]);
    try expectEqual(21, get_buf[1]);

    // The queue is now empty, so `get` should return `error.Closed` too
    try expectError(error.Closed, queue.getOne(io));
    try expectError(error.Closed, queue.get(io, &get_buf, 0));
    try expectError(error.Closed, queue.putUncancelable(io, &get_buf, 2));
}

test "Event smoke test" {
    const io = testing.io;

    var event: Io.Event = .unset;
    try testing.expectEqual(false, event.isSet());

    // make sure the event gets set
    event.set(io);
    try testing.expectEqual(true, event.isSet());

    // make sure the event gets unset again
    event.reset();
    try testing.expectEqual(false, event.isSet());

    // waits should timeout as there's no other thread to set the event
    try testing.expectError(error.Timeout, event.waitTimeout(io, .{ .duration = .{
        .raw = .zero,
        .clock = .awake,
    } }));
    try testing.expectError(error.Timeout, event.waitTimeout(io, .{ .duration = .{
        .raw = .fromMilliseconds(1),
        .clock = .awake,
    } }));

    // set the event again and make sure waits complete
    event.set(io);
    try event.wait(io);
    try event.waitTimeout(io, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } });
    try testing.expectEqual(true, event.isSet());
}

test "Event signaling" {
    if (builtin.single_threaded) {
        // This test requires spawning threads.
        return error.SkipZigTest;
    }

    const io = testing.io;

    const Context = struct {
        in: Io.Event = .unset,
        out: Io.Event = .unset,
        value: usize = 0,

        fn input(self: *@This()) !void {
            // wait for the value to become 1
            try self.in.wait(io);
            self.in.reset();
            try testing.expectEqual(self.value, 1);

            // bump the value and wake up output()
            self.value = 2;
            self.out.set(io);

            // wait for output to receive 2, bump the value and wake us up with 3
            try self.in.wait(io);
            self.in.reset();
            try testing.expectEqual(self.value, 3);

            // bump the value and wake up output() for it to see 4
            self.value = 4;
            self.out.set(io);
        }

        fn output(self: *@This()) !void {
            // start with 0 and bump the value for input to see 1
            try testing.expectEqual(self.value, 0);
            self.value = 1;
            self.in.set(io);

            // wait for input to receive 1, bump the value to 2 and wake us up
            try self.out.wait(io);
            self.out.reset();
            try testing.expectEqual(self.value, 2);

            // bump the value to 3 for input to see (rhymes)
            self.value = 3;
            self.in.set(io);

            // wait for input to bump the value to 4 and receive no more (rhymes)
            try self.out.wait(io);
            self.out.reset();
            try testing.expectEqual(self.value, 4);
        }
    };

    var ctx = Context{};

    const thread = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, Context.output, .{&ctx});
    defer thread.join();

    try ctx.input();
}

test "Event broadcast" {
    if (builtin.single_threaded) {
        // This test requires spawning threads.
        return error.SkipZigTest;
    }

    const io = testing.io;

    const num_threads = 10;
    const Barrier = struct {
        event: Io.Event = .unset,
        counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(num_threads),

        fn wait(self: *@This()) void {
            if (self.counter.fetchSub(1, .acq_rel) == 1) {
                self.event.set(io);
            }
        }
    };

    const Context = struct {
        start_barrier: Barrier = .{},
        finish_barrier: Barrier = .{},

        fn run(self: *@This()) void {
            self.start_barrier.wait();
            self.finish_barrier.wait();
        }
    };

    var ctx = Context{};
    var threads: [num_threads - 1]std.Thread = undefined;

    for (&threads) |*t| t.* = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, Context.run, .{&ctx});
    defer for (threads) |t| t.join();

    ctx.run();
}

test Semaphore {
    if (builtin.single_threaded) return error.SkipZigTest;
    const io = testing.io;

    const TestContext = struct {
        sem: *Semaphore,
        n: *i32,
        fn worker(ctx: *@This()) !void {
            try ctx.sem.wait(io);
            ctx.n.* += 1;
            ctx.sem.post(io);
        }
    };
    const num_threads = 3;
    var sem: Semaphore = .{ .permits = 1 };
    var threads: [num_threads]std.Thread = undefined;
    var n: i32 = 0;
    var ctx = TestContext{ .sem = &sem, .n = &n };

    for (&threads) |*t| t.* = try std.Thread.spawn(.{
        .allocator = testing.allocator,
    }, TestContext.worker, .{&ctx});
    for (threads) |t| t.join();
    try sem.wait(io);
    try testing.expect(n == num_threads);
}

test "RwLock internal state" {
    const io = testing.io;

    var rl: Io.RwLock = .init;

    rl.lockUncancelable(io);
    rl.unlock(io);
    try testing.expectEqual(rl, Io.RwLock.init);
}

test "RwLock smoke test" {
    const io = testing.io;

    var rl: Io.RwLock = .init;

    rl.lockUncancelable(io);
    try testing.expect(!rl.tryLock(io));
    try testing.expect(!rl.tryLockShared(io));
    rl.unlock(io);

    try testing.expect(rl.tryLock(io));
    try testing.expect(!rl.tryLock(io));
    try testing.expect(!rl.tryLockShared(io));
    rl.unlock(io);

    rl.lockSharedUncancelable(io);
    try testing.expect(!rl.tryLock(io));
    try testing.expect(rl.tryLockShared(io));
    rl.unlockShared(io);
    rl.unlockShared(io);

    try testing.expect(rl.tryLockShared(io));
    try testing.expect(!rl.tryLock(io));
    try testing.expect(rl.tryLockShared(io));
    rl.unlockShared(io);
    rl.unlockShared(io);

    rl.lockUncancelable(io);
    rl.unlock(io);
}

test "RwLock concurrent access" {
    if (builtin.single_threaded) return;

    const io = testing.io;
    const num_writers: usize = 2;
    const num_readers: usize = 4;
    const num_writes: usize = 1000;
    const num_reads: usize = 2000;

    const Runner = struct {
        const Runner = @This();

        io: Io,

        rl: Io.RwLock,
        writes: usize,
        reads: std.atomic.Value(usize),

        val_a: usize,
        val_b: usize,

        fn reader(run: *Runner, thread_idx: usize) !void {
            var prng = std.Random.DefaultPrng.init(thread_idx);
            const rnd = prng.random();
            while (true) {
                run.rl.lockSharedUncancelable(run.io);
                defer run.rl.unlockShared(run.io);

                try testing.expect(run.writes <= num_writes);
                if (run.reads.fetchAdd(1, .monotonic) >= num_reads) break;

                // We use `volatile` accesses so that we can make sure the memory is accessed either
                // side of a yield, maximising chances of a race.
                const a_ptr: *const volatile usize = &run.val_a;
                const b_ptr: *const volatile usize = &run.val_b;

                const old_a = a_ptr.*;
                if (rnd.boolean()) try std.Thread.yield();
                const old_b = b_ptr.*;
                try testing.expect(old_a == old_b);
            }
        }

        fn writer(run: *Runner, thread_idx: usize) !void {
            var prng = std.Random.DefaultPrng.init(thread_idx);
            const rnd = prng.random();
            while (true) {
                run.rl.lockUncancelable(run.io);
                defer run.rl.unlock(run.io);

                try testing.expect(run.writes <= num_writes);
                if (run.writes == num_writes) break;

                // We use `volatile` accesses so that we can make sure the memory is accessed either
                // side of a yield, maximising chances of a race.
                const a_ptr: *volatile usize = &run.val_a;
                const b_ptr: *volatile usize = &run.val_b;

                const new_val = rnd.int(usize);

                const old_a = a_ptr.*;
                a_ptr.* = new_val;
                if (rnd.boolean()) try std.Thread.yield();
                const old_b = b_ptr.*;
                b_ptr.* = new_val;
                try testing.expect(old_a == old_b);

                run.writes += 1;
            }
        }
    };

    var run: Runner = .{
        .io = io,
        .rl = .init,
        .writes = 0,
        .reads = .init(0),
        .val_a = 0,
        .val_b = 0,
    };
    var write_threads: [num_writers]std.Thread = undefined;
    var read_threads: [num_readers]std.Thread = undefined;

    for (&write_threads, 0..) |*t, i| t.* = try .spawn(.{
        .allocator = testing.allocator,
    }, Runner.writer, .{ &run, i });
    for (&read_threads, num_writers..) |*t, i| t.* = try .spawn(.{
        .allocator = testing.allocator,
    }, Runner.reader, .{ &run, i });

    for (write_threads) |t| t.join();
    for (read_threads) |t| t.join();

    try testing.expect(run.writes == num_writes);
    try testing.expect(run.reads.raw >= num_reads);
}

const testing = std.testing;
const expect = testing.expect;
const expectEqual  = testing.expectEqual;
const expectError = testing.expectError;

const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;

const Semaphore = Io.Semaphore;
