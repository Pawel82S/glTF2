/*
Usage:

```odin
import gltf "gltf2"

buf := gltf.buffer_slice(data, accessor_index).([][3]f32)
for val, i in buf {
    // ...
}
```

Alternatively you can use a switch statement to handle multiple data formats:

```odin
buf := gltf.buffer_slice(data, accessor_index)
#partial switch vals in buf {
case [][4]u8:
    for val, i in vals { 
        // ...
    }
case [][4]i16:
    for val, i in vals {
        // ...
    }
}
```                           
*/
package gltf2

import "core:mem"

// All accessor type and component type combinations
Buffer_Slice :: union {
    []u8,
    []i8,
    []i16,
    []u16,
    []u32,
    []f32,
    [][2]u8,
    [][2]i8,
    [][2]i16,
    [][2]u16,
    [][2]u32,
    [][2]f32,
    [][3]u8,
    [][3]i8,
    [][3]i16,
    [][3]u16,
    [][3]u32,
    [][3]f32,
    [][4]u8,
    [][4]i8,
    [][4]i16,
    [][4]u16,
    [][4]u32,
    [][4]f32,
    []matrix[2, 2]u8,
    []matrix[2, 2]i8,
    []matrix[2, 2]i16,
    []matrix[2, 2]u16,
    []matrix[2, 2]u32,
    []matrix[2, 2]f32,
    []matrix[3, 3]u8,
    []matrix[3, 3]i8,
    []matrix[3, 3]i16,
    []matrix[3, 3]u16,
    []matrix[3, 3]u32,
    []matrix[3, 3]f32,
    []matrix[4, 4]u8,
    []matrix[4, 4]i8,
    []matrix[4, 4]i16,
    []matrix[4, 4]u16,
    []matrix[4, 4]u32,
    []matrix[4, 4]f32,
}

buffer_slice :: proc(data: ^Data, accessor_index: Integer) -> Buffer_Slice {
    accessor := data.accessors[accessor_index]
    assert(accessor.buffer_view != nil, "buf_iter_make: selected accessor doesn't have buffer_view")

    buffer_view := data.buffer_views[accessor.buffer_view.?]

    if _, ok := accessor.sparse.?; ok {
        assert(false, "Sparse not supported")
        return nil
    }

    if _, ok := buffer_view.byte_stride.?; ok {
        assert(false, "Cannot use a stride")
        return nil
    }

    start_byte := accessor.byte_offset + buffer_view.byte_offset
    uri := data.buffers[buffer_view.buffer].uri

    switch v in uri {
    case string:
        assert(false, "URI is string")
        return nil
    case []byte:
        start_ptr: rawptr = &v[start_byte]
        switch accessor.type {
        case .Scalar:
            switch accessor.component_type {
            case .Unsigned_Byte:
                return (transmute([^]u8)start_ptr)[:accessor.count]
            case .Byte:
                return (transmute([^]i8)start_ptr)[:accessor.count]
            case .Short:
                return (transmute([^]i16)start_ptr)[:accessor.count]
            case .Unsigned_Short:
                return (transmute([^]u16)start_ptr)[:accessor.count]
            case .Unsigned_Int:
                return (transmute([^]u32)start_ptr)[:accessor.count]
            case .Float:
                return (transmute([^]f32)start_ptr)[:accessor.count]
            }

        case .Vector2:
            switch accessor.component_type {
            case .Unsigned_Byte:
                return (transmute([^][2]u8)start_ptr)[:accessor.count]
            case .Byte:
                return (transmute([^][2]i8)start_ptr)[:accessor.count]
            case .Short:
                return (transmute([^][2]i16)start_ptr)[:accessor.count]
            case .Unsigned_Short:
                return (transmute([^][2]u16)start_ptr)[:accessor.count]
            case .Unsigned_Int:
                return (transmute([^][2]u32)start_ptr)[:accessor.count]
            case .Float:
                return (transmute([^][2]f32)start_ptr)[:accessor.count]
            }

        case .Vector3:
            switch accessor.component_type {
            case .Unsigned_Byte:
                return (transmute([^][3]u8)start_ptr)[:accessor.count]
            case .Byte:
                return (transmute([^][3]i8)start_ptr)[:accessor.count]
            case .Short:
                return (transmute([^][3]i16)start_ptr)[:accessor.count]
            case .Unsigned_Short:
                return (transmute([^][3]u16)start_ptr)[:accessor.count]
            case .Unsigned_Int:
                return (transmute([^][3]u32)start_ptr)[:accessor.count]
            case .Float:
                return (transmute([^][3]f32)start_ptr)[:accessor.count]
            }

        case .Vector4:
            switch accessor.component_type {
            case .Unsigned_Byte:
                return (transmute([^][4]u8)start_ptr)[:accessor.count]
            case .Byte:
                return (transmute([^][4]i8)start_ptr)[:accessor.count]
            case .Short:
                return (transmute([^][4]i16)start_ptr)[:accessor.count]
            case .Unsigned_Short:
                return (transmute([^][4]u16)start_ptr)[:accessor.count]
            case .Unsigned_Int:
                return (transmute([^][4]u32)start_ptr)[:accessor.count]
            case .Float:
                return (transmute([^][4]f32)start_ptr)[:accessor.count]
            }

        case .Matrix2:
            switch accessor.component_type {
            case .Unsigned_Byte:
                return (transmute([^]matrix[2, 2]u8)start_ptr)[:accessor.count]
            case .Byte:
                return (transmute([^]matrix[2, 2]i8)start_ptr)[:accessor.count]
            case .Short:
                return (transmute([^]matrix[2, 2]i16)start_ptr)[:accessor.count]
            case .Unsigned_Short:
                return (transmute([^]matrix[2, 2]u16)start_ptr)[:accessor.count]
            case .Unsigned_Int:
                return (transmute([^]matrix[2, 2]u32)start_ptr)[:accessor.count]
            case .Float:
                return (transmute([^]matrix[2, 2]f32)start_ptr)[:accessor.count]
            }

        case .Matrix3:
            switch accessor.component_type {
            case .Unsigned_Byte:
                return (transmute([^]matrix[3, 3]u8)start_ptr)[:accessor.count]
            case .Byte:
                return (transmute([^]matrix[3, 3]i8)start_ptr)[:accessor.count]
            case .Short:
                return (transmute([^]matrix[3, 3]i16)start_ptr)[:accessor.count]
            case .Unsigned_Short:
                return (transmute([^]matrix[3, 3]u16)start_ptr)[:accessor.count]
            case .Unsigned_Int:
                return (transmute([^]matrix[3, 3]u32)start_ptr)[:accessor.count]
            case .Float:
                return (transmute([^]matrix[3, 3]f32)start_ptr)[:accessor.count]
            }

        case .Matrix4:
            switch accessor.component_type {
            case .Unsigned_Byte:
                return (transmute([^]matrix[4, 4]u8)start_ptr)[:accessor.count]
            case .Byte:
                return (transmute([^]matrix[4, 4]i8)start_ptr)[:accessor.count]
            case .Short:
                return (transmute([^]matrix[4, 4]i16)start_ptr)[:accessor.count]
            case .Unsigned_Short:
                return (transmute([^]matrix[4, 4]u16)start_ptr)[:accessor.count]
            case .Unsigned_Int:
                return (transmute([^]matrix[4, 4]u32)start_ptr)[:accessor.count]
            case .Float:
                return (transmute([^]matrix[4, 4]f32)start_ptr)[:accessor.count]
            }

        }
    }

    return nil
}
