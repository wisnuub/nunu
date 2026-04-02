#include "avm/gpu/gpu_renderer.h"
#include <iostream>
#include <vector>

// SDL2 + OpenGL fallback renderer
// Used when Vulkan is unavailable (older GPU drivers).
#include <SDL2/SDL.h>
#include <SDL2/SDL_opengl.h>

namespace avm {

/**
 * OpenGLRenderer — host-side desktop OpenGL 3.3 fallback.
 *
 * Presents decoded frames by uploading the RGBA8 framebuffer to a
 * full-screen quad texture via glTexSubImage2D.
 *
 * Rendering pipeline:
 *   FrameBuffer (RGBA8 pixels from gfxstream)
 *       │
 *   glTexSubImage2D → VBO fullscreen quad
 *       │
 *   GLSL shader: passthrough (texture sample only)
 *       │
 *   SDL2 OpenGL window
 */
class OpenGLRenderer : public GpuRenderer {
public:
    bool initialize(int width, int height, const std::string& title) override {
        width_  = width;
        height_ = height;

        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            std::cerr << "[OpenGL] SDL_Init failed: " << SDL_GetError() << "\n";
            return false;
        }

        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
                            SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

        window_ = SDL_CreateWindow(
            title.c_str(),
            SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
            width, height,
            SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_SHOWN
        );
        if (!window_) {
            std::cerr << "[OpenGL] SDL_CreateWindow failed: " << SDL_GetError() << "\n";
            return false;
        }

        gl_ctx_ = SDL_GL_CreateContext(window_);
        if (!gl_ctx_) {
            std::cerr << "[OpenGL] SDL_GL_CreateContext failed: " << SDL_GetError() << "\n";
            return false;
        }

        // Vsync off for gaming (let FramePresenter control FPS)
        SDL_GL_SetSwapInterval(0);

        if (!setup_framebuffer_texture()) return false;
        if (!setup_fullscreen_quad())    return false;

        ready_ = true;
        std::cout << "[OpenGL] Renderer initialized (" << width << "x" << height << ").\n";
        return true;
    }

    void shutdown() override {
        if (tex_)    { glDeleteTextures(1, &tex_);    tex_    = 0; }
        if (vao_)    { glDeleteVertexArrays(1, &vao_); vao_   = 0; }
        if (vbo_)    { glDeleteBuffers(1, &vbo_);      vbo_   = 0; }
        if (shader_) { glDeleteProgram(shader_);       shader_ = 0; }
        if (gl_ctx_) { SDL_GL_DeleteContext(gl_ctx_); gl_ctx_ = nullptr; }
        if (window_) { SDL_DestroyWindow(window_);    window_ = nullptr; }
        SDL_Quit();
        ready_ = false;
        std::cout << "[OpenGL] Renderer shut down.\n";
    }

    void process_command_buffer(const uint8_t* cmdbuf, size_t size) override {
        // TODO: decode gfxstream GLES command stream.
        // For OpenGL path, decoded GLES calls are translated to
        // desktop GL 3.3 calls. ANGLE handles this translation on
        // the Vulkan path; here we do it directly.
        (void)cmdbuf; (void)size;
    }

    void present_frame(const FrameBuffer& fb) override {
        if (!ready_ || !fb.data) return;

        // Upload RGBA8 pixel data to the full-screen texture
        glBindTexture(GL_TEXTURE_2D, tex_);
        glTexSubImage2D(GL_TEXTURE_2D, 0,
                        0, 0, fb.width, fb.height,
                        GL_RGBA, GL_UNSIGNED_BYTE, fb.data);

        // Draw fullscreen quad
        glClear(GL_COLOR_BUFFER_BIT);
        glUseProgram(shader_);
        glBindVertexArray(vao_);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        SDL_GL_SwapWindow(window_);
    }

    void handle_resize(int new_width, int new_height) override {
        width_  = new_width;
        height_ = new_height;
        glViewport(0, 0, new_width, new_height);
        // Recreate texture at new size
        glDeleteTextures(1, &tex_);
        tex_ = 0;
        setup_framebuffer_texture();
    }

    bool is_ready() const override { return ready_; }
    const char* backend_name() const override { return "OpenGL"; }

private:
    bool setup_framebuffer_texture() {
        glGenTextures(1, &tex_);
        glBindTexture(GL_TEXTURE_2D, tex_);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        // Allocate RGBA8 texture at display size (filled by present_frame)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8,
                     width_, height_, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        return tex_ != 0;
    }

    bool setup_fullscreen_quad() {
        // NDC fullscreen quad: positions + UVs interleaved
        // pos(xy) uv(xy) — triangle strip
        static const float quad[] = {
            -1.0f,  1.0f,  0.0f, 0.0f,   // top-left
            -1.0f, -1.0f,  0.0f, 1.0f,   // bottom-left
             1.0f,  1.0f,  1.0f, 0.0f,   // top-right
             1.0f, -1.0f,  1.0f, 1.0f,   // bottom-right
        };
        glGenVertexArrays(1, &vao_);
        glGenBuffers(1, &vbo_);
        glBindVertexArray(vao_);
        glBindBuffer(GL_ARRAY_BUFFER, vbo_);
        glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
        // position
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE,
                              4 * sizeof(float), (void*)0);
        glEnableVertexAttribArray(0);
        // texcoord
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE,
                              4 * sizeof(float), (void*)(2 * sizeof(float)));
        glEnableVertexAttribArray(1);

        // Compile minimal passthrough shaders
        const char* vert_src = R"(
            #version 330 core
            layout(location=0) in vec2 aPos;
            layout(location=1) in vec2 aUV;
            out vec2 vUV;
            void main() { gl_Position = vec4(aPos, 0.0, 1.0); vUV = aUV; }
        )";
        const char* frag_src = R"(
            #version 330 core
            in vec2 vUV;
            out vec4 FragColor;
            uniform sampler2D uTex;
            void main() { FragColor = texture(uTex, vUV); }
        )";

        auto compile = [](GLenum type, const char* src) -> GLuint {
            GLuint s = glCreateShader(type);
            glShaderSource(s, 1, &src, nullptr);
            glCompileShader(s);
            GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
            if (!ok) {
                char log[512]; glGetShaderInfoLog(s, 512, nullptr, log);
                std::cerr << "[OpenGL] Shader error: " << log << "\n";
            }
            return s;
        };

        GLuint vs = compile(GL_VERTEX_SHADER, vert_src);
        GLuint fs = compile(GL_FRAGMENT_SHADER, frag_src);
        shader_ = glCreateProgram();
        glAttachShader(shader_, vs); glAttachShader(shader_, fs);
        glLinkProgram(shader_);
        glDeleteShader(vs); glDeleteShader(fs);

        glUseProgram(shader_);
        glUniform1i(glGetUniformLocation(shader_, "uTex"), 0);
        return true;
    }

    int        width_ = 0, height_ = 0;
    bool       ready_ = false;
    SDL_Window* window_  = nullptr;
    SDL_GLContext gl_ctx_ = nullptr;
    GLuint tex_    = 0;
    GLuint vao_    = 0;
    GLuint vbo_    = 0;
    GLuint shader_ = 0;
};

std::unique_ptr<GpuRenderer> create_opengl_renderer() {
    return std::make_unique<OpenGLRenderer>();
}

} // namespace avm
