ServerEvents.recipes(event => {
  event.shaped(
  Item.of('minecraft:ender_pearl', 2),
  [
    'AAA',
    'ABA', 
    'AAA'
  ],
  {
    A: 'minecraft:glass',
    B: 'minecraft:emerald'
  })
})