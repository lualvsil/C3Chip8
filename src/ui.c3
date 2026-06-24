module chip;

import std::math;
import raylib6;

const RLColor TEXT_COLOR = rl::WHITE;
const RLColor VIEW_BACKGROUND = rl::BLUE;
const RLColor VIEW_BACKGROUND_PRESSED = { 0, 60, 120, 172 };

const char*[] KEYMAP = {
	"1", "2", "3", "C",
	"4", "5", "6", "D",
	"7", "8", "9", "E",
	"A", "0", "B", "F",
};
const char[] KEYCODE = {
	1,   2, 3,   0xC,
	4,   5, 6,   0xD,
	7,   8, 9,   0xE,
	0xA, 0, 0xB, 0xF,
};
struct KeypadView {
	RLRectangle rect;
	RLVector2 keySize;
}
// Return position in keypad matrix
fn int KeypadView.process_touch(KeypadView self, RLVector2 touch)
{
	if (touch.x < self.rect.x || touch.x > self.rect.x+self.rect.width ||
		touch.y < self.rect.y || touch.y > self.rect.y+self.rect.height)
	{
		return -1;
	}
	touch.y -= self.rect.y;
	int col=math::min((int)(touch.x / self.keySize.x), 3);
	int row=math::min((int)(touch.y / self.keySize.y), 3);
	return KEYCODE[row*4+col];
}
fn void KeypadView.draw(KeypadView self, char[16]* keypad)
{
	foreach (idx, key : KEYMAP) {
		int col=(int)(idx%4);
		int row=(int)(idx/4);

		rl::draw_rectangle_rec(
			{
				2 + self.keySize.x*col,
				2 + self.rect.y + self.keySize.y*row,
				self.keySize.x-4,
				self.keySize.y-4,
			},
			!((*keypad)[KEYCODE[idx]]==1) ?
					VIEW_BACKGROUND : VIEW_BACKGROUND_PRESSED
		);
		rl::draw_text(
			(ZString)key,
			(int)(2+self.keySize.x*col + (self.keySize.x/4)),
			(int)(2+self.rect.y + self.keySize.y*row + (self.keySize.y/2)),
			(int)(self.keySize.y/2),
			TEXT_COLOR,
		);
	}
}

struct Button {
	RLRectangle rect;
	String text;
	bool current;
	bool previous;
}
fn void Button.process_touch(Button* self, RLVector2 touch)
{
	if (touch.x >= self.rect.x && touch.x <= self.rect.x+self.rect.width &&
		touch.y >= self.rect.y && touch.y <= self.rect.y+self.rect.height)
	{
		self.current = true;
	}
}
fn void Button.update(Button* self)
{
	self.previous = self.current;
	self.current=false;
}
fn bool Button.released(Button self) {
	return (self.previous && !self.current);
}
fn void Button.draw(Button self)
{
	rl::draw_rectangle_rec(
		{
			self.rect.x,
			self.rect.y,
			self.rect.width,
			self.rect.height,
		},
		(!self.previous) ? 
				VIEW_BACKGROUND : VIEW_BACKGROUND_PRESSED
	);
	rl::draw_text(
		(ZString)self.text,
		(int)(self.rect.x),
		(int)(self.rect.y),
		(int)(self.rect.height*0.5),
		TEXT_COLOR,
	);
}
