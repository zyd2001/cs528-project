# Gradio Server CVE 2024-47167 Exploit Demo

## Running the Exploit

The exploit can be ran manually using the provided python files. It can also be
run using nix

### Running with Python scripts

This exploit runs on Python 3. The commands below may need to use `python3`
instead of `python` and `pip3` instead of `pip`.

First the **exact** dependencies must be installed by running,
```bash
pip install -r requirements.txt
```

Now the setup is complete,
```bash
python server.py # Launches the vulnerable Gradio server
python exploit.py <url> # To download the contents of the url onto the server
```

Some url responses are compressed so they are not readable without decompression.

### Running with Nix (with Flakes Enabled)

To run the server with nix, there are two options.
```bash
nix run .#gradio-server # Runs the server standalone
nix run .#gradio-server-vm # Runs the server in a resource constrained vm
```

Then to run the exploit,
```bash
nix run .#expoit -- <url> # Runs the exploit, downloading the contents of the
                          # url provided to the server
```


