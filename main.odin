package main

import "core:fmt"
import "core:mem"
import "gltf2"


test :: proc() {
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

    fmt.println("====================ASSET======================")
    fmt.println(data.asset)
    fmt.println()
    fmt.println("====================ACCESSORS==================")
    fmt.println(data.accessors)
    fmt.println()
    fmt.println("====================ANIMATIONS=================")
    fmt.println(data.animations)
    fmt.println()
    fmt.println("====================BUFFERS====================")
    fmt.println(data.buffers)
    fmt.println()
    fmt.println("====================BUFFER VIEWS===============")
    fmt.println(data.buffer_views)
    fmt.println()
    fmt.println("====================CAMERAS====================")
    fmt.println(data.cameras)
    fmt.println()
    fmt.println("====================IMAGES=====================")
    fmt.println(data.images)
    fmt.println()
    fmt.println("====================NODES======================")
    fmt.println(data.nodes)
    fmt.println()
    fmt.println("====================MATERIALS==================")
    fmt.println(data.materials)
    fmt.println()
    fmt.println("====================MESHES=====================")
    fmt.println(data.meshes)
    fmt.println()
    fmt.println("====================SAMPLERS===================")
    fmt.println(data.samplers)
    fmt.println()
    fmt.println("====================SCENES=====================")
    fmt.println("Current scene:", data.scene)
    fmt.println(data.scenes)
    fmt.println()
    fmt.println("====================TEXTURES===================")
    fmt.println(data.textures)
    fmt.println()
    fmt.println("====================EXTENSIONS=================")
    fmt.println("Extensions used:", data.extensions_used)
    fmt.println()
    fmt.println("Extensions required:", data.extensions_required)
    fmt.println()
    fmt.println("====================OTHER======================")
    fmt.println("Size of Data struct:", size_of(gltf2.Data))

    //data := [?]u32{ GLB_MAGIC, 2, 0 }
    //header := (cast(^GLB_Header)(raw_data(data[:])))^
    //mem.copy(&header, raw_data(data[:]), GLB_HEADER_SIZE)
    //fmt.println(header)
}

main :: proc() {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)

    test()

    total_leak_size: int
    for _, leak in track.allocation_map {
        fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
        total_leak_size += leak.size
    }
    if total_leak_size > 0 do fmt.printf("Total leak size: %v bytes\n", total_leak_size)
    for bad_free in track.bad_free_array {
        fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
    }
} 
