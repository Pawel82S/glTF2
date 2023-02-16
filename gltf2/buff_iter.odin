/*!!
Helper procedures to iterate over buffer elements using provided accessor

```odin
for it := buf_iter_make([3]f32, &accesor, data); it.idx < it.count; it.idx += 1 {
    elem = buf_iter_elem(&it)
}```
*/
package gltf2

import "core:mem"


Buffer_Iterator :: struct($T: typeid) {
    buf: []byte,
    count, idx, stride: Integer,
}

buf_iter_make :: proc($T: typeid, accessor: ^Accessor, data: ^Data) -> (res: Buffer_Iterator(T)) {
    assert(accessor.buffer_view != nil, "buf_iter_make: selected accessor doesn't have buffer_view")

    component_size := 1
    #partial switch accessor.type {
    //case .Scalar: component_size = 1
    case .Vector2: component_size = 2
    case .Vector3: component_size = 3
    case .Vector4, .Matrix2: component_size = 4
    case .Matrix3: component_size = 9
    case .Matrix4: component_size = 16
    }

    #partial switch accessor.component_type {
    //case .Byte, .Unsigned_Byte: component_size *= 1
    case .Short, .Unsigned_Short: component_size *= 2
    case .Unsigned_Int, .Float: component_size *= 4
    }

    assert(size_of(T) == component_size, "buf_iter_make: element type size is not the same as accessor")

    buffer_view := data.buffer_views[accessor.buffer_view.?]
    res.stride = buffer_view.byte_stride.? or_else 0

    start_byte := accessor.byte_offset + buffer_view.byte_offset
    end_byte := start_byte + accessor.count * (size_of(T) + res.stride)
    uri := data.buffers[buffer_view.buffer].uri

    // TODO: Add safety check to ensure uri is of type `[]byte`
    res.buf = uri.([]byte)[start_byte:end_byte]

    res.count = accessor.count
    return res
}

buf_iter_elem :: proc(it: ^Buffer_Iterator($T)) -> (res: T) {
    start_byte := it.idx * (size_of(T) + it.stride)
    mem.copy(&res, raw_data(it.buf[start_byte:]), size_of(T))
    return res
}
