return {
    display_id = 1,
    server_channel = 100,
    listen_channel = 120,
    
    update_interval = 2,
    request_timeout = 5,
    
    monitor = {
        side = "auto",
        text_scale = 0.9
    },
    
    display = {
        show_alerts = true,
        max_alerts = 5,
        show_graphs = true,
        graph_history = 50
    },
    
    colors = {
        background = colors.black,
        text = colors.white,
        header = colors.yellow,
        active = colors.lime,
        inactive = colors.red,
        warning = colors.orange,
        critical = colors.red,
        good = colors.lime,
        border = colors.gray
    }
}