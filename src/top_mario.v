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

    wire pad_left, pad_right;
    gamepad_pmod_single gamepad (
        .rst_n(rst_n),
        .clk(clk),
        .pmod_latch(ui_in[4]),
        .pmod_clk(ui_in[5]),
        .pmod_data(ui_in[6]),
        .b(), .y(), .select(), .start(), .up(), .down(),
        .left(pad_left),
        .right(pad_right),
        .a(), .x(), .l(), .r(), .is_present()
    );

    reg [9:0] scrollOffset;
    wire frame_tick = (pix_x == 10'd0) && (pix_y == 10'd480);
    localparam [9:0] PLAYER_MIN_X = 10'd16;
    localparam [9:0] PLAYER_MAX_X = 10'd608;
    reg [9:0] player_x;
    reg player_right;
    reg [2:0] walk_phase;
    reg walk_frame;
    wire step_left = pad_left && !pad_right && (player_x > PLAYER_MIN_X);
    wire step_right = pad_right && !pad_left && (player_x < PLAYER_MAX_X);
    always @(posedge clk) begin
        if (!rst_n) begin
            scrollOffset <= 10'd0;
            player_x <= 10'd48;
            player_right <= 1'b1;
            walk_phase <= 3'd0;
            walk_frame <= 1'b0;
        end else if (frame_tick) begin
            if (ui_in[0] && !ui_in[1]) begin
              scrollOffset <= (scrollOffset == 10'd0)
                            ? 10'd0 : scrollOffset - 10'd1;
            end
            if (!ui_in[0] && ui_in[1]) begin
              scrollOffset <= (scrollOffset == 10'd640)
                            ? 10'd640 : scrollOffset + 10'd1;
            end

            if (step_left || step_right) begin
                player_x <= step_right ? player_x + 10'd2 : player_x - 10'd2;
                player_right <= step_right;
                walk_phase <= walk_phase + 3'd1;
                if (walk_phase == 3'd7) walk_frame <= ~walk_frame;
            end else begin
                walk_phase <= 3'd0;
                walk_frame <= 1'b0;
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

    // The background ROM returns the pixel two clocks after its coordinates.
    // Delay the coordinates and actor state by the same amount before overlaying
    // the sprite, so it remains aligned with the map and VGA sync signals.
    reg [9:0] pix_x_d1, pix_x_d2, pix_y_d1, pix_y_d2;
    reg [9:0] player_x_d1, player_x_d2;
    reg walk_frame_d1, walk_frame_d2;
    reg player_right_d1, player_right_d2;
    always @(posedge clk) begin
        if (!rst_n) begin
            pix_x_d1 <= 10'd0;
            pix_x_d2 <= 10'd0;
            pix_y_d1 <= 10'd0;
            pix_y_d2 <= 10'd0;
            player_x_d1 <= 10'd0;
            player_x_d2 <= 10'd0;
            walk_frame_d1 <= 1'b0;
            walk_frame_d2 <= 1'b0;
            player_right_d1 <= 1'b1;
            player_right_d2 <= 1'b1;
        end else begin
            pix_x_d1 <= pix_x;
            pix_x_d2 <= pix_x_d1;
            pix_y_d1 <= pix_y;
            pix_y_d2 <= pix_y_d1;
            player_x_d1 <= player_x;
            player_x_d2 <= player_x_d1;
            walk_frame_d1 <= walk_frame;
            walk_frame_d2 <= walk_frame_d1;
            player_right_d1 <= player_right;
            player_right_d2 <= player_right_d1;
        end
    end

    localparam [9:0] PLAYER_Y = 10'd408;
    wire sprite_in_box = (pix_x_d2 >= player_x_d2) &&
                         (pix_x_d2 < player_x_d2 + 10'd16) &&
                         (pix_y_d2 >= PLAYER_Y) &&
                         (pix_y_d2 < PLAYER_Y + 10'd24);
    wire [3:0] sprite_local_x = pix_x_d2 - player_x_d2;
    wire [3:0] sprite_x = player_right_d2 ? sprite_local_x : 4'd15 - sprite_local_x;
    wire [4:0] sprite_y = pix_y_d2 - PLAYER_Y;
    wire [6:0] sprite_pixel_data = sprite_pixel(sprite_x, sprite_y, walk_frame_d2);
    wire [5:0] final_color = (sprite_in_box && sprite_pixel_data[6])
                           ? sprite_pixel_data[5:0] : bg_color;

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

    // 16x24 pixel-art character. Bit 6 marks an opaque pixel; bit 5:0 is RGB222.
    function [6:0] sprite_pixel;
        input [3:0] sx;
        input [4:0] sy;
        input frame;
        reg opaque;
        reg [5:0] rgb;
        begin
            opaque = 1'b0;
            rgb = 6'b0;

            // Red cap and hair.
            if ((sy <= 2 && sx >= 5 && sx <= 10) ||
                (sy == 3 && sx >= 3 && sx <= 12)) begin
                opaque = 1'b1; rgb = 6'b110000;
            end else if (sy >= 4 && sy <= 8 && sx >= 4 && sx <= 11) begin
                opaque = 1'b1; rgb = 6'b111001;
                if ((sx == 9 && sy >= 5 && sy <= 6) ||
                    (sx == 4 && sy == 8)) rgb = 6'b000000;
            end

            // Red shirt and arms.
            if ((sy >= 9 && sy <= 14 && sx >= 4 && sx <= 11) ||
                (sy >= 10 && sy <= 13 && (sx == 2 || sx == 3 || sx == 12 || sx == 13))) begin
                opaque = 1'b1; rgb = 6'b110000;
            end

            // Blue overalls.
            if (sy >= 12 && sy <= 17 && sx >= 5 && sx <= 10) begin
                opaque = 1'b1; rgb = 6'b000111;
                if ((sx == 6 || sx == 9) && sy == 12) rgb = 6'b111001;
            end

            // Walking legs alternate between two simple poses.
            if (sy >= 18 && sy <= 21) begin
                if ((!frame && ((sx >= 4 && sx <= 6) || (sx >= 9 && sx <= 11))) ||
                    ( frame && ((sx >= 3 && sx <= 5) || (sx >= 10 && sx <= 12)))) begin
                    opaque = 1'b1; rgb = 6'b000111;
                end
            end
            if (sy >= 22 && sy <= 23) begin
                if ((!frame && ((sx >= 3 && sx <= 6) || (sx >= 9 && sx <= 12))) ||
                    ( frame && ((sx >= 2 && sx <= 5) || (sx >= 10 && sx <= 13)))) begin
                    opaque = 1'b1; rgb = 6'b110000;
                end
            end
            sprite_pixel = {opaque, rgb};
        end
    endfunction
endmodule
