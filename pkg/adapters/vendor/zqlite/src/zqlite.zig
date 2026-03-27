const std = @import("std");
pub const c = @cImport(@cInclude("sqlite3.h"));

pub const Pool = @import("pool.zig").Pool;

const conn = @import("conn.zig");
pub const Conn = conn.Conn;
pub const Row = conn.Row;
pub const Rows = conn.Rows;
pub const Stmt = conn.Stmt;
pub const ColumnType = conn.ColumnType;

pub fn open(path: [*:0]const u8, flags: c_int) !Conn {
    return Conn.init(path, flags);
}

// a marker type so we can tell if the provided []const u8 should be treated as
// a text or a blob
pub const Blob = struct {
    value: []const u8,
};

pub fn blob(value: []const u8) Blob {
    return .{ .value = value };
}

pub fn isUnique(err: Error) bool {
    return err == error.ConstraintUnique;
}

pub const OpenFlags = struct {
    pub const Create = c.SQLITE_OPEN_CREATE;
    pub const ReadOnly = c.SQLITE_OPEN_READONLY;
    pub const ReadWrite = c.SQLITE_OPEN_READWRITE;
    pub const DeleteOnClose = c.SQLITE_OPEN_DELETEONCLOSE;
    pub const Exclusive = c.SQLITE_OPEN_EXCLUSIVE;
    pub const AutoProxy = c.SQLITE_OPEN_AUTOPROXY;
    pub const Uri = c.SQLITE_OPEN_URI;
    pub const Memory = c.SQLITE_OPEN_MEMORY;
    pub const MainDB = c.SQLITE_OPEN_MAIN_DB;
    pub const TempDB = c.SQLITE_OPEN_TEMP_DB;
    pub const TransientDB = c.SQLITE_OPEN_TRANSIENT_DB;
    pub const MainJournal = c.SQLITE_OPEN_MAIN_JOURNAL;
    pub const TempJournal = c.SQLITE_OPEN_TEMP_JOURNAL;
    pub const SubJournal = c.SQLITE_OPEN_SUBJOURNAL;
    pub const SuperJournal = c.SQLITE_OPEN_SUPER_JOURNAL;
    pub const NoMutex = c.SQLITE_OPEN_NOMUTEX;
    pub const FullMutex = c.SQLITE_OPEN_FULLMUTEX;
    pub const SharedCache = c.SQLITE_OPEN_SHAREDCACHE;
    pub const PrivateCache = c.SQLITE_OPEN_PRIVATECACHE;
    pub const OpenWAL = c.SQLITE_OPEN_WAL;
    pub const NoFollow = c.SQLITE_OPEN_NOFOLLOW;
    pub const EXResCode = c.SQLITE_OPEN_EXRESCODE;
};

pub const Error = error{
    Abort,
    Auth,
    Busy,
    CantOpen,
    Constraint,
    Corrupt,
    Empty,
    Error,
    Format,
    Full,
    Internal,
    Interrupt,
    IoErr,
    Locked,
    Mismatch,
    Misuse,
    NoLFS,
    NoMem,
    NotADB,
    Notfound,
    Notice,
    Perm,
    Protocol,
    Range,
    ReadOnly,
    Schema,
    TooBig,
    Warning,
    ErrorMissingCollseq,
    ErrorRetry,
    ErrorSnapshot,
    IoerrRead,
    IoerrShortRead,
    IoerrWrite,
    IoerrFsync,
    IoerrDir_fsync,
    IoerrTruncate,
    IoerrFstat,
    IoerrUnlock,
    IoerrRdlock,
    IoerrDelete,
    IoerrBlocked,
    IoerrNomem,
    IoerrAccess,
    IoerrCheckreservedlock,
    IoerrLock,
    IoerrClose,
    IoerrDirClose,
    IoerrShmopen,
    IoerrShmsize,
    IoerrShmlock,
    ioerrshmmap,
    IoerrSeek,
    IoerrDeleteNoent,
    IoerrMmap,
    IoerrGetTempPath,
    IoerrConvPath,
    IoerrVnode,
    IoerrAuth,
    IoerrBeginAtomic,
    IoerrCommitAtomic,
    IoerrRollbackAtomic,
    IoerrData,
    IoerrCorruptFS,
    LockedSharedCache,
    LockedVTab,
    BusyRecovery,
    BusySnapshot,
    BusyTimeout,
    CantOpenNoTempDir,
    CantOpenIsDir,
    CantOpenFullPath,
    CantOpenConvPath,
    CantOpenDirtyWal,
    CantOpenSymlink,
    CorruptVTab,
    CorruptSequence,
    CorruptIndex,
    ReadonlyRecovery,
    ReadonlyCantlock,
    ReadonlyRollback,
    ReadonlyDbMoved,
    ReadonlyCantInit,
    ReadonlyDirectory,
    AbortRollback,
    ConstraintCheck,
    ConstraintCommithook,
    ConstraintForeignKey,
    ConstraintFunction,
    ConstraintNotNull,
    ConstraintPrimaryKey,
    ConstraintTrigger,
    ConstraintUnique,
    ConstraintVTab,
    ConstraintRowId,
    ConstraintPinned,
    ConstraintDatatype,
    NoticeRecoverWal,
    NoticeRecoverRollback,
    WarningAutoIndex,
    AuthUser,
    OkLoadPermanently,
};

test {
    std.testing.refAllDecls(@This());
}
