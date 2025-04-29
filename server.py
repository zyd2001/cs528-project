# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "gradio==4.44.1",
#     "pydantic==2.10.6",
# ]
# ///
import gradio as gr

print(gr.__version__)

def upload_file(files):
    file_paths = [file.name for file in files]
    return file_paths


with gr.Blocks() as demo:
    file_output = gr.File()
    upload_button = gr.UploadButton("Click to Upload an Image or Video File", file_types=["image", "video"], file_count="multiple")
    upload_button.upload(upload_file, upload_button, file_output)


demo.launch(server_name="0.0.0.0")
