const ngeohash = require('ngeohash');
console.log('lat, lng ->', ngeohash.encode(17.385, 78.487, 5));
console.log('lng, lat ->', ngeohash.encode(78.487, 17.385, 5));
