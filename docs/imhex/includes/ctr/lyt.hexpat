import std.array;
import std.mem;
import type.magic;
import type.size;

namespace auto ctr {
    namespace auto lyt {
        struct Header<auto ExpectedMagic> {
            type::Magic<ExpectedMagic> signature;
            std::mem::Bytes<2> endian;
            u16 header_size;
            u32 version;
            type::Size32 file_size;
            u32 blocks;
        };

        struct BlockHeader {
            char kind[4];
            type::Size32 size;
        };
    }
}
