package main

import "core:fmt"
import "core:mem"
import "gltf2"


main :: proc() {
    TEST_FILE :: "assets/gltf/cube.gltf"
    data, error := gltf2.load_from_file(TEST_FILE, true)
    switch err in error {
    case gltf2.JSON_Error:
        fmt.println(err)
        return
    case gltf2.GLTF_Error:
        fmt.println(err)
        return
    }
    defer gltf2.unload(data)

    fmt.println(data.asset)
    fmt.println()
    fmt.println(data.accessors)
    fmt.println()
    fmt.println("Scene:", data.scene)
    fmt.println()
    fmt.println(data.scenes)
    fmt.println()
    fmt.println(data.buffers)
    fmt.println()
    fmt.println(data.buffer_views)
    fmt.println()
    fmt.println(data.images)
    fmt.println()
    fmt.println(data.nodes)
    fmt.println()
    fmt.println(data.materials)
    fmt.println()
    fmt.println(data.meshes)
    fmt.println()
    fmt.println("Extensions used:", data.extensions_used)
    fmt.println()
    fmt.println("Extensions required:", data.extensions_required)
    fmt.println()
    fmt.println("Size of Data", size_of(gltf2.Data))
    //data := [?]u32{ GLB_MAGIC, 2, 0 }
    //header := (cast(^GLB_Header)(raw_data(data[:])))^
    //mem.copy(&header, raw_data(data[:]), GLB_HEADER_SIZE)
    //fmt.println(header)
} 
