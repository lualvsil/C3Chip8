module chip;

import std::thread;
import std::io;
import raylib6;

int width;
int height;

char[] font = {
	0xf0, 0x90, 0x90, 0x90, 0xf0, // 0
	0x20, 0x60, 0x20, 0x20, 0x70, // 1
	0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
	0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
	0x90, 0x90, 0xF0, 0x10, 0x10, // 4
	0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
	0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
	0xF0, 0x10, 0x20, 0x40, 0x40, // 7
	0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
	0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
	0xF0, 0x90, 0xF0, 0x90, 0x90, // A
	0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
	0xF0, 0x80, 0x80, 0x80, 0xF0, // C
	0xE0, 0x90, 0x90, 0x90, 0xE0, // D
	0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
	0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

struct Chip8 {
	int tickRate;
	char[64][32] display;
	ushort pendingIns;

	char[4096] ram;
	char[16] keyboard;
	ushort[16] stack;
	
	char[16] vx; // General purpose register
	char dr, sr; // Delay and time register
	char sp;
	ushort ir; // Memory address register
	ushort pc;

	bool paused;
}
fn void Chip8.load(Chip8* chip8, Cart cart) {
	chip8.reset();
	chip8.tickRate = cart.second;
	foreach (i, byte : cart.first) {
		chip8.ram[0x200+i] = byte;
	}
}
fn void Chip8.reset(Chip8* chip8)
{
	chip8.tickRate = 0;
	chip8.pc = 0x200;
	chip8.cls();
	chip8.sp = 0;
	chip8.dr = 0;
	chip8.sr = 0;
	chip8.ir = 0;
	chip8.pendingIns = 0;
	chip8.paused = false;
	foreach (&byte : chip8.ram) {
		byte = (char*)0;
	}
	foreach (&register : chip8.vx) {
		register = (char*)0;
	}
	foreach (idx, c : font) {
		chip8.ram[idx] = c;
	}
}

fn void Chip8.cls(Chip8* chip8) {
	for (int j=0; j<32; j++) {
		for (int i=0; i<64; i++) {
			chip8.display[j][i] = 0;
		}
	}
}

fn bool Chip8.draw_sprite(Chip8* chip8, int x, int y, int n)
{
	x = chip8.vx[x];
	y = chip8.vx[y];
	bool collision=false;
	for (int i=0; i<n; i++) {
		char sprite=chip8.ram[chip8.ir+i];
		for (int j=0; j<8; j++) {
			char pixel=(sprite >> (7-j)) & 1;
			int px = (x + j) % 64;
			int py = (y + i) % 32;
			if (chip8.display[py][px] && pixel) {
				collision = true;
			}
			chip8.display[py][px] ^= pixel;
		}
	}
	return collision;
}
fn void Chip8.execute_next_instruction(Chip8* chip8)
{
	char ophi = chip8.ram[chip8.pc];
	char oplo = chip8.ram[chip8.pc+1];

	bool incPc = true;

	switch (ophi & 0xf0) {
	case 0x00:
		if (oplo == 0xEE) { // RET
			chip8.sp -= 1;
			chip8.pc = chip8.stack[chip8.sp];
			incPc = false;
		} else if (oplo == 0xE0) { // CLS
			chip8.cls();
		} else {
			nextcase default;
		}
	case 0x10: // 1nnn JP nnn
		ushort adr = ((ushort)(ophi & 0x0f) << 8) |
					 ((ushort)oplo);
		
		chip8.pc = adr;
		incPc = false;
	case 0x20: // 2nnn CALL nnn
		ushort adr = ((ushort)(ophi & 0x0f) << 8) |
					 ((ushort)oplo);

		chip8.stack[chip8.sp] = chip8.pc+2;
		chip8.sp += 1;

		chip8.pc = adr;
		incPc = false;
	case 0x30: // 3xkk SE Vx, kk
		int reg = ophi & 0x0f;
		if (chip8.vx[reg] == oplo) {
			chip8.pc += 2;
		}
	case 0x40: // 4xkk SNE Vx, kk
		int reg = ophi & 0x0f;
		if (chip8.vx[reg] != oplo) {
			chip8.pc += 2;
		}
	case 0x50: // 5xy0 SE Vx, Vy
		int xr = ophi & 0x0f;
		int yr = (oplo & 0xf0) >> 4;
		if (chip8.vx[xr] == chip8.vx[yr]) {
			chip8.pc += 2;
		}
	case 0x60: // 6xkk LD Vx, kk
		int reg = ophi & 0x0f;
		chip8.vx[reg] = oplo;
	case 0x70: // 7xkk ADD Vx, kk
		char reg = ophi & 0x0f;
		chip8.vx[reg] += oplo;
	case 0x80: // 8xy*
		char xr = ophi & 0x0f;
		int yr = (oplo & 0xf0) >> 4;
		ichar flag = -1;
		switch (oplo & 0x0f) {
		case 0: // LD Vx, Vy
			chip8.vx[xr] = chip8.vx[yr];
		case 1: // OR Vx, Vy
			chip8.vx[xr] = chip8.vx[xr] | chip8.vx[yr];
			flag = 0;
		case 2: // AND Vx, Vy
			chip8.vx[xr] = chip8.vx[xr] & chip8.vx[yr];
			flag = 0;
		case 3: // XOR Vx, Vy
			chip8.vx[xr] = chip8.vx[xr] ^ chip8.vx[yr];
			flag = 0;
		case 4: // ADD Vx, Vy
			flag = (ichar)((ushort)chip8.vx[yr] + (ushort)chip8.vx[xr] > 255) ? 1 : 0;
			chip8.vx[xr] = chip8.vx[xr] + chip8.vx[yr];
		case 5: // SUB Vx, Vy
			flag = (ichar)(chip8.vx[xr] >= chip8.vx[yr]);
			chip8.vx[xr] = chip8.vx[xr] - chip8.vx[yr];
		case 6: // SHR Vx, Vy
			flag = (ichar)(chip8.vx[yr] & 1 == 1);
			chip8.vx[xr] = chip8.vx[yr] >> 1;
		case 7: // SUBN Vx, Vy
			flag = (ichar)(chip8.vx[yr] >= chip8.vx[xr]);
			chip8.vx[xr] = chip8.vx[yr] - chip8.vx[xr];
		case 0xE: // SHL Vx, Vy
			flag = (ichar)(chip8.vx[yr] >> 7 == 1);
			chip8.vx[xr] = chip8.vx[yr] << 1;
		default:
			chip8.paused=true;
			chip8.pendingIns = ((ushort)ophi << 8) | oplo;
			break;
		}
		if (flag > -1) {
			chip8.vx[0xf] = (flag) ? 1 : 0;
		}
	case 0x90: // 9xy0 SNE Vx, Vy
		char xr = ophi & 0x0f;
		char yr = (oplo & 0xf0) >> 4;
		if (chip8.vx[xr] != chip8.vx[yr]) {
			chip8.pc += 2;
		}
	case 0xA0: // Annn LD I, nnn
		chip8.ir = ((ushort)(ophi & 0x0f) << 8) |
					((ushort)oplo);
	case 0xB0: // Bnnn JP V0, addr
		chip8.pc = chip8.vx[0] + ((((ushort)ophi & 0xf) << 8) | oplo);
		incPc = false;
	case 0xC0: // Cxkk RND Vx, kk
		int reg = ophi & 0x0f;
		chip8.vx[reg] = (char)rl::get_random_value(0,255) & oplo;
	case 0xD0: // Dxyn DRW Vx, Vy, nibble
		int x=ophi&0x0f;
		int y=(oplo&0xf0) >> 4;
		int n=oplo&0x0f;
		chip8.vx[0xf] = (char)chip8.draw_sprite(x, y, n);
	case 0xE0:
		int xr = chip8.vx[ophi&0x0f];
		if (oplo == 0x9e) if (chip8.keyboard[xr] >> 1) chip8.pc += 2;
		if (oplo == 0xa1) if (!(chip8.keyboard[xr] >> 1)) chip8.pc += 2;
	case 0xF0:
		int xr = ophi & 0x0f;
		switch (oplo) {
		case 0x07: // LD Vx, DT
			chip8.vx[xr] = chip8.dr;
		case 0x0A:
			foreach (idx, key : chip8.keyboard) {
				if (key == 0b01) {
					chip8.pc += 2;
					chip8.vx[xr] = (char)idx;
				}
			}
			incPc = false;
		case 0x15: // LD DT, Vx
			chip8.dr = chip8.vx[xr];
		case 0x18:
			chip8.sr = chip8.vx[xr];
		case 0x1E: // ADD I, Vx
			chip8.ir += chip8.vx[xr];
		case 0x29:
			chip8.ir = (chip8.vx[xr] & 0x0f) * 5;
		case 0x33:
			chip8.ram[chip8.ir] = chip8.vx[xr] / 100;
			chip8.ram[chip8.ir+1] = chip8.vx[xr] / 10 % 10;
			chip8.ram[chip8.ir+2] = chip8.vx[xr] % 10;
		case 0x55: // LD [I], Vx
			for (int i=0; i<=xr; i++) {
				chip8.ram[chip8.ir] = chip8.vx[i];
				chip8.ir++;
			}
		case 0x65: // LD Vx, [I]
			for (int i=0; i<=xr; i++) {
				chip8.vx[i] = chip8.ram[chip8.ir];
				chip8.ir++;
			}
		default:
			chip8.paused=true;
			chip8.pendingIns = ((ushort)ophi << 8) | (ushort)oplo;
			break;
		}
	default:
		chip8.paused=true;
		chip8.pendingIns = ((ushort)ophi << 8) | (ushort)oplo;
		break;
	}

	if (incPc && !chip8.paused) {
		chip8.pc += 2;
	}
}
fn void Chip8.update(Chip8* chip8) {
	for (int i=0; i<chip8.tickRate; i++) {
		if (!chip8.paused) {
			chip8.execute_next_instruction();
		}
	}

	chip8.dr -= (chip8.dr) ? 1 : 0;
	chip8.sr -= (chip8.sr) ? 1 : 0;
	
	foreach (idx, key : chip8.keyboard) {
		chip8.keyboard[idx] = key >> 1;
	}
}
fn void Chip8.drawDisplay(Chip8 chip8)
{
	int pixelSize = width / 64;
	int leftPadding = (width - pixelSize*64) / 2;
	int topPadding = (height / 4) - 16 * pixelSize;
	for (int j=0; j<32; j++) {
		for (int i=0; i<64; i++) {
			rl::draw_rectangle(
				pixelSize*i + leftPadding,
				pixelSize*j + topPadding,
				pixelSize, pixelSize,
				(chip8.display[j][i]) ? rl::BLACK : rl::GRAY);
		}
	}
}

fn void printText(char[] txt, int x, int y)
{
	int size=40;
	rl::draw_text((ZString)txt, x, y, size, rl::GREEN);
}

fn void Chip8.printRegs(Chip8 chip8)
{
	char[2048] txtBuf;
	int bottom=0;
	for (int i=0; i<16; i++) {
		io::bprintf(&txtBuf, "V%x = %d\0", i, chip8.vx[i]);
		printText(&txtBuf, 50, height/2 + 40*(i+1));
		bottom=height/2 + 40*(i+1);
	}
	
	bottom+=40;
	io::bprintf(&txtBuf, "PC: %x\0", chip8.pc);
	printText(&txtBuf, 50, bottom);

	bottom+=40;
	io::bprintf(&txtBuf, "I = %x\0", chip8.ir);
	printText(&txtBuf, 50, bottom);
	

	bottom+=40;
	io::bprintf(&txtBuf, "TR = %x\0", chip8.sr);
	printText(&txtBuf, 50, bottom);
	
	bottom+=40;
	io::bprintf(&txtBuf, "SP = %x\0", chip8.sp);
	printText(&txtBuf, 50, bottom);
	
	bottom+=40;
	io::bprintf(&txtBuf, "Pause = %d\0", chip8.paused);
	printText(&txtBuf, 50, bottom);
	
	bottom+=40;
	io::bprintf(&txtBuf, "Ticks = %d\0", chip8.tickRate);
	printText(&txtBuf, 50, bottom);

	if (chip8.pendingIns) {
		bottom+=40;
		io::bprintf(&txtBuf, "Pending = %x\0", chip8.pendingIns);
		printText(&txtBuf, 50, bottom);
	}
}


fn void buzzer_gen_beep(void* bufferData, uint frames)
{
	float* buffer=(float*)bufferData;
	for (uint i = 0; i < frames; i++) {
		if (!global_buzzer.buzz) {
			buffer[i] = 0;
			continue;
		}
		uint wave_length = global_buzzer.sample_rate/440;
		if (((uint)global_buzzer.wave_index / wave_length) % 2 == 0) {
			buffer[i] = 1;
		} else {
			buffer[i] = -1;
		}
		global_buzzer.wave_index++;
	}
}

struct Buzzer {
	RLAudioStream stream;
	int wave_index;
	bool buzz;
	uint sample_rate;
	uint sample_size;
}
fn void Buzzer.init(Buzzer* self)
{
	self.sample_rate = 44100;
	self.sample_size = 32;
	self.wave_index = 0;
	self.buzz = false;
	
	self.stream = rl::load_audio_stream(self.sample_rate, self.sample_size, 1);
	self.stream.set_callback(&buzzer_gen_beep);
	rl::play_audio_stream(self.stream);
}
fn void Buzzer.set_active(Buzzer* self, bool active)
{
	if (active) {
		rl::resume_audio_stream(self.stream);
	} else {
		rl::pause_audio_stream(self.stream);
	}
}

Buzzer* global_buzzer;

fn int main(int argc, char** argv)
{
	rl::init_window(0,0, "C3 CHIP-8");
	rl::init_audio_device();
	rl::set_target_fps(60);

	const int ABSIZE=512;

	rl::set_audio_stream_buffer_size_default(ABSIZE);

	global_buzzer = mem::new(Buzzer);
	global_buzzer.init();
	
	width = rl::get_screen_width();
	height = rl::get_screen_height();

	KeypadView keypadView = {
		.rect = {
			.x=0, .y=height / 2.0f,
			.width=width, .height=height / 2.0f,
		},
		.keySize = {
			.x = width / 4.0f,
			.y = height / 8.0f,
		}
	};
	Button selectButton = {
		{
			0,0,
			width/4.0f,
			height*0.05f,
		},
		"SELECT", false, false
	};
	Button debugButton = {
		{
			width - width/4.0f ,0,
			width/4.0f,
			(int)(height*0.05),
		},
		"DEBUG", false, false
	};
	Button audioButton = {
		{
			width/2.0f - (width/8.0f), 0,
			width/4.0f,
			(int)(height*0.05),
		},
		"AUDIO", false, false
	};

	char[2048] txtBuf;

	Chip8* chip8=null;

	bool romSelector=true;
	int scroll=0;
	int totalScroll=0;
	bool isSliding=false;

	RLVector2 touchStart;
	RLVector2 touchLast;
	bool hasTouchLast=false;

	bool debugView;
	bool playAudio=true;

	while (!rl::window_should_close()) {
		// List of ROMs
		if (romSelector) {
			int boxH = height / 10;
			rl::begin_drawing();
			rl::clear_background(rl::GRAY);

			// Draw List
			foreach (int idx, name : romnames) {
				rl::draw_rectangle(
					10, boxH*idx+2 - scroll,
					width-20, boxH-4,
					rl::BLUE
				);
				rl::draw_text(
					(ZString)name,
					20, boxH*idx+2 + boxH/8 - scroll,
					boxH / 4,
					rl::WHITE,
				);
			}

			// Slide or select
			if (rl::get_touch_point_count() > 0) {
				touchStart = rl::get_touch_position(0);
				if (hasTouchLast) {
					int diff = (int)(touchLast.y - touchStart.y);
					totalScroll += (diff > 0) ? diff : -diff;
					if (scroll + diff < 0 || scroll+diff > boxH*(int)romnames.len - height) {
						diff = 0;
					}
					scroll += diff;
					if (totalScroll > 5) isSliding=true;
				}
				touchLast = touchStart;
				hasTouchLast = true;
			} else {
				if (!isSliding && hasTouchLast) {
					int idx = (int)(touchLast.y+scroll) / boxH;
					if (idx < romnames.len) {
						romSelector = false;
						if (chip8 != null) mem::free(chip8);
						chip8 = mem::new(Chip8);
						chip8.load(roms[idx]);
					}
				}
				hasTouchLast = false;
				totalScroll=0;
				isSliding=false;
			}

			rl::end_drawing();
			continue;
		}

		// Emulator loop
		for (int i=0; i<rl::get_touch_point_count(); i++) {
			RLVector2 touch = rl::get_touch_position(i);

			// Open Selector
			(&selectButton).process_touch(touch);
			(&debugButton).process_touch(touch);
			(&audioButton).process_touch(touch);
			
			int index = keypadView.process_touch(touch);
			if (index != -1) {
				chip8.keyboard[index] |= 0b10;
			}
		}
		
		if (selectButton.released()) {
			romSelector = true;
			thread::sleep_ms(200);
		}
		if (debugButton.released()) debugView=(debugView) ? false : true;
		if (audioButton.released()) {
			playAudio ^= true;
			global_buzzer.set_active(playAudio);
		}

		global_buzzer.buzz = (chip8.sr != 0);
		
		(&selectButton).update();
		(&debugButton).update();
		(&audioButton).update();
		
		chip8.update();

		rl::begin_drawing();
		rl::clear_background(rl::GRAY);

		chip8.drawDisplay();
		keypadView.draw(&chip8.keyboard);

		selectButton.draw();
		debugButton.draw();
		audioButton.draw();

		// Debug Info
		if (debugView) {
			io::bprintf(&txtBuf, "%d\0", rl::get_fps());
			printText(&txtBuf, width / 2, 100);
			chip8.printRegs();
		}

		rl::end_drawing();
	}

	rl::unload_audio_stream(global_buzzer.stream);
	rl::close_audio_device();
	rl::close_window();
	return 0;
}
