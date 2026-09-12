// @ts-check

// Native en-US date controls start with the month segment. Type through the
// keyboard so input handlers run between digits without refocusing the field.
export async function typeNativeDate(page, input, digits) {
  await input.click({ position: { x: 20, y: 20 } });
  await page.keyboard.type(digits, { delay: 40 });
}

export async function replaceNativeYear(page, input, year) {
  await input.click({ position: { x: 20, y: 20 } });
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  await page.keyboard.type(year, { delay: 40 });
}
