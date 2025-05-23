/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#pragma once
#include "Falcor.h"
#include "Core/SampleApp.h"
#include "Core/Pass/RasterPass.h"
#include "RenderGraph/RenderGraph.h"
#include "Scene/SceneBuilder.h"

using namespace Falcor;

struct Vertex
{
    float3 position{};
    //float3 color{};
};

class Raytracing : public SampleApp
{
public:
    Raytracing(const SampleAppConfig& config);
    ~Raytracing();

    void onLoad(RenderContext* pRenderContext) override;
    void onResize(uint32_t width, uint32_t height) override;
    void onFrameRender(RenderContext* pRenderContext, const ref<Fbo>& pTargetFbo) override;
    void onGuiRender(Gui* pGui) override;
    bool onKeyEvent(const KeyboardEvent& keyEvent) override;
    bool onMouseEvent(const MouseEvent& mouseEvent) override;

private:
    ref<RasterPass> raster_pass_;

    ref<Program> program_;
    ref<ProgramVars> program_vars_;
    ref<Buffer> vertex_buffer_;
    ref<VertexBufferLayout> vertex_buffer_layout_;
    ref<VertexLayout> vertex_layout_;
    ref<Vao> vao_;

    ref<Program> rt_program_;
    ref<RtProgramVars> rt_program_vars_;

    //SceneBuilder scene_builder_ = SceneBuilder;
    ref<Scene> mpScene;
    ref<Camera> mpCamera;
    bool mUseDOF = false;
    uint32_t mSampleIndex = 0;
    ref<Texture> mpRtOut;

    //void loadScene(const std::filesystem::path& path, const Fbo* pTargetFbo);
    //void setPerFrameVars(const Fbo* pTargetFbo);
    ////void renderRaster(RenderContext* pRenderContext, const ref<Fbo>& pTargetFbo);
    //void renderRT(RenderContext* pRenderContext, const ref<Fbo>& pTargetFbo);

    //ref<Scene> mpScene;
    //ref<Camera> mpCamera;

    ////ref<RasterPass> mpRasterPass;

    //ref<Program> mpRaytraceProgram;
    //ref<RtProgramVars> mpRtVars;
    //ref<Texture> mpRtOut;

    //bool mRayTrace = true;
    //bool mUseDOF = false;

    //uint32_t mSampleIndex = 0xdeadbeef;
};
