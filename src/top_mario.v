`timescale 1ns / 1ps

// Moving background with an animated, gamepad-controlled character.
// Compatible with the original Tiny Tapeout VGA pin assignment.
module tt_um_vga_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire hsync_raw, vsync_raw, display_on_raw;
    wire [9:0] pix_x, pix_y;

    hvsync_generator vga_sync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync_raw),
        .vsync(vsync_raw),
        .display_on(display_on_raw),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    wire pad_left, pad_right, pad_a;
    gamepad_pmod_single gamepad (
        .rst_n(rst_n),
        .clk(clk),
        .pmod_latch(ui_in[4]),
        .pmod_clk(ui_in[5]),
        .pmod_data(ui_in[6]),
        .b(), .y(), .select(), .start(), .up(), .down(),
        .left(pad_left),
        .right(pad_right),
        .a(pad_a), .x(), .l(), .r(), .is_present()
    );

    reg [9:0] scrollOffset;
    wire frame_tick = (pix_x == 10'd0) && (pix_y == 10'd480);
    localparam [9:0] PLAYER_WIDTH = 10'd32;
    localparam [9:0] PLAYER_HEIGHT = 10'd48;
    localparam [9:0] PLAYER_MIN_X = 10'd0;
    localparam [9:0] PLAYER_MAX_X = 10'd640 - PLAYER_WIDTH;
    localparam [9:0] WALK_SPEED = 10'd4;
    localparam [9:0] MAX_SCROLL = 10'd640;
    localparam [9:0] CAMERA_FOLLOW_LEFT = 10'd160;
    localparam [9:0] CAMERA_FOLLOW_RIGHT = (10'd640 - PLAYER_WIDTH) / 2;
    localparam [9:0] GROUND_Y = 10'd384;
    localparam [9:0] PLAYER_GROUND_Y = GROUND_Y - PLAYER_HEIGHT;
    localparam signed [5:0] JUMP_SPEED = 6'sd11;
    reg [9:0] player_x;
    reg player_right;
    reg [1:0] walk_phase;
    reg walk_frame;
    reg pad_a_prev, jump_pending;
    reg [6:0] jump_height;
    reg signed [5:0] jump_velocity;
    wire airborne = (jump_height != 7'd0);
    wire jump_pressed = pad_a && !pad_a_prev;
    wire signed [7:0] next_jump_height = $signed({1'b0, jump_height}) + jump_velocity;
    wire walk_left = pad_left && !pad_right;
    wire walk_right = pad_right && !pad_left;
    wire scroll_left = walk_left && (player_x <= CAMERA_FOLLOW_LEFT) &&
                       (scrollOffset != 10'd0);
    wire scroll_right = walk_right && (player_x >= CAMERA_FOLLOW_RIGHT) &&
                        (scrollOffset != MAX_SCROLL);
    wire step_left = walk_left && !scroll_left && (player_x > PLAYER_MIN_X);
    wire step_right = walk_right && !scroll_right && (player_x < PLAYER_MAX_X);
    wire walking = step_left || step_right || scroll_left || scroll_right;
    always @(posedge clk) begin
        if (!rst_n) begin
            scrollOffset <= 10'd0;
            player_x <= 10'd48;
            player_right <= 1'b1;
            walk_phase <= 2'd0;
            walk_frame <= 1'b0;
        end else if (frame_tick) begin
            // Scroll before the sprite reaches the screen edge. At the
            // world boundary, let it finish walking across the screen.
            if (scroll_left) begin
                scrollOffset <= (scrollOffset < WALK_SPEED)
                              ? 10'd0 : scrollOffset - WALK_SPEED;
            end else if (scroll_right) begin
                scrollOffset <= (scrollOffset > MAX_SCROLL - WALK_SPEED)
                              ? MAX_SCROLL : scrollOffset + WALK_SPEED;
            end else if (!walk_left && !walk_right) begin
                if (ui_in[0] && !ui_in[1] && (scrollOffset != 10'd0))
                    scrollOffset <= scrollOffset - 10'd1;
                else if (!ui_in[0] && ui_in[1] && (scrollOffset != MAX_SCROLL))
                    scrollOffset <= scrollOffset + 10'd1;
            end

            if (step_left)
                player_x <= player_x - WALK_SPEED;
            else if (step_right)
                player_x <= player_x + WALK_SPEED;

            if (walking)
                player_right <= walk_right;

            if (walking && !airborne) begin
                walk_phase <= walk_phase + 2'd1;
                if (&walk_phase) walk_frame <= ~walk_frame;
            end else begin
                walk_phase <= 2'd0;
                walk_frame <= 1'b0;
            end
        end
    end

    // Capture short A presses between video frames. Airborne presses
    // are ignored, so each jump requires a fresh press from the ground.
    always @(posedge clk) begin
        if (!rst_n) begin
            pad_a_prev <= 1'b0;
            jump_pending <= 1'b0;
            jump_height <= 7'd0;
            jump_velocity <= 6'sd0;
        end else begin
            pad_a_prev <= pad_a;
            if (frame_tick) begin
                jump_pending <= 1'b0;
                if (airborne) begin
                    if (next_jump_height <= 8'sd0) begin
                        jump_height <= 7'd0;
                        jump_velocity <= 6'sd0;
                    end else begin
                        jump_height <= next_jump_height[6:0];
                        jump_velocity <= jump_velocity - 6'sd1;
                    end
                end else if (jump_pending || jump_pressed) begin
                    jump_height <= {1'b0, JUMP_SPEED};
                    jump_velocity <= JUMP_SPEED - 6'sd1;
                end
            end else if (jump_pressed && !airborne) begin
                jump_pending <= 1'b1;
            end
        end
    end

    wire [10:0] x_scroll = {1'b0, pix_x} + {1'b0, scrollOffset};
    wire [5:0] bg_color;
    bg_renderer background (
        .clk(clk),
        .reset(~rst_n),
        .x_scroll(x_scroll),
        .y(pix_y),
        .color(bg_color)
    );

    // Twelve 8x8 tiles, drawn at 2x scale. Bit 6 marks an opaque pixel.
    // The poses share the top four tiles and use separate bottom pairs.
    reg [6:0] player_tiles [0:767];
    initial $readmemh("../data/player_tiles.mem", player_tiles);

    wire [9:0] sprite_dx = pix_x - player_x;
    wire [9:0] sprite_dy = pix_y - (PLAYER_GROUND_Y - {3'b000, jump_height});
    wire sprite_in_box = (sprite_dx < PLAYER_WIDTH) && (sprite_dy < PLAYER_HEIGHT);
    wire [3:0] sprite_x = player_right ? sprite_dx[4:1] : ~sprite_dx[4:1];
    wire [4:0] sprite_y = sprite_dy[5:1];
    wire [2:0] leg_tile_row = airborne ? {2'b10, (jump_velocity <= 6'sd0)}
                                     : {2'b01, walk_frame};
    wire [2:0] tile_row = sprite_y[4] ? leg_tile_row : {2'b00, sprite_y[3]};
    wire [9:0] sprite_address = {tile_row, sprite_x[3], sprite_y[2:0], sprite_x[2:0]};

    // Match the background's two-clock pixel pipeline.
    reg [6:0] sprite_pixel_d1, sprite_pixel_d2;
    always @(posedge clk) begin
        if (!rst_n) begin
            sprite_pixel_d1 <= 7'd0;
            sprite_pixel_d2 <= 7'd0;
        end else begin
            sprite_pixel_d1 <= sprite_in_box ? player_tiles[sprite_address] : 7'd0;
            sprite_pixel_d2 <= sprite_pixel_d1;
        end
    end

    wire [5:0] final_color = sprite_pixel_d2[6] ? sprite_pixel_d2[5:0] : bg_color;

    // ROM pipeline delays RGB by 2 cycles compared with pixel coordinates.
    // VGA sync generator already registers sync once, so delay sync 1 more.
    reg active_d1, active_d2;
    reg hsync_d1, vsync_d1;
    always @(posedge clk) begin
        if (!rst_n) begin
            active_d1 <= 1'b0;
            active_d2 <= 1'b0;
            hsync_d1 <= 1'b1;
            vsync_d1 <= 1'b1;
        end else begin
            active_d1 <= display_on_raw;
            active_d2 <= active_d1;
            hsync_d1 <= hsync_raw;
            vsync_d1 <= vsync_raw;
        end
    end

    wire [1:0] R = active_d2 ? final_color[5:4] : 2'b00;
    wire [1:0] G = active_d2 ? final_color[3:2] : 2'b00;
    wire [1:0] B = active_d2 ? final_color[1:0] : 2'b00;

    assign uo_out = {hsync_d1, B[0], G[0], R[0],
                     vsync_d1, B[1], G[1], R[1]};
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    wire _unused_ok = &{ena, ui_in, uio_in};
endmodule
