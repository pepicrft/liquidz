const { render } = require('./index');

console.log('Testing Liquidz Node.js binding...\n');

// Test 1: Simple variable
const result1 = render('Hello, {{ name }}!', { name: 'World' });
console.log('Test 1 - Simple variable:', result1);
console.assert(result1 === 'Hello, World!', 'Test 1 failed');

// Test 2: Loop
const result2 = render('{% for item in items %}{{ item }} {% endfor %}', { items: ['a', 'b', 'c'] });
console.log('Test 2 - Loop:', result2);
console.assert(result2 === 'a b c ', 'Test 2 failed');

// Test 3: Conditional
const result3 = render('{% if show %}visible{% else %}hidden{% endif %}', { show: true });
console.log('Test 3 - Conditional:', result3);
console.assert(result3 === 'visible', 'Test 3 failed');

// Test 4: Filters
const result4 = render('{{ name | upcase }}', { name: 'hello' });
console.log('Test 4 - Filter:', result4);
console.assert(result4 === 'HELLO', 'Test 4 failed');

// Test 5: JSON string data
const result5 = render('{{ x }}', '{"x": 42}');
console.log('Test 5 - JSON string:', result5);
console.assert(result5 === '42', 'Test 5 failed');

// Test 6: Empty data
const result6 = render('Hello');
console.log('Test 6 - Empty data:', result6);
console.assert(result6 === 'Hello', 'Test 6 failed');

// Test 7: Nested objects
const result7 = render('{{ user.name }}', { user: { name: 'Alice' } });
console.log('Test 7 - Nested objects:', result7);
console.assert(result7 === 'Alice', 'Test 7 failed');

console.log('\nAll tests passed!');
