#include "WindowsNativeEngine.h"

namespace vielotus_win {

namespace {

constexpr int kMaxWordTokens = WindowsNativeEngine::kMaxWordTokens;
constexpr int kMaxUtf8Bytes = WindowsNativeEngine::kMaxUtf8Bytes;

constexpr wchar_t V0[12][6] = {
    { 0x0061, 0x00E1, 0x00E0, 0x1EA3, 0x00E3, 0x1EA1 },
    { 0x0103, 0x1EAF, 0x1EB1, 0x1EB3, 0x1EB5, 0x1EB7 },
    { 0x00E2, 0x1EA5, 0x1EA7, 0x1EA9, 0x1EAB, 0x1EAD },
    { 0x0065, 0x00E9, 0x00E8, 0x1EBB, 0x1EBD, 0x1EB9 },
    { 0x00EA, 0x1EBF, 0x1EC1, 0x1EC3, 0x1EC5, 0x1EC7 },
    { 0x0069, 0x00ED, 0x00EC, 0x1EC9, 0x0129, 0x1ECB },
    { 0x006F, 0x00F3, 0x00F2, 0x1ECF, 0x00F5, 0x1ECD },
    { 0x00F4, 0x1ED1, 0x1ED3, 0x1ED5, 0x1ED7, 0x1ED9 },
    { 0x01A1, 0x1EDB, 0x1EDD, 0x1EDF, 0x1EE1, 0x1EE3 },
    { 0x0075, 0x00FA, 0x00F9, 0x1EE7, 0x0169, 0x1EE5 },
    { 0x01B0, 0x1EE9, 0x1EEB, 0x1EED, 0x1EEF, 0x1EF1 },
    { 0x0079, 0x00FD, 0x1EF3, 0x1EF7, 0x1EF9, 0x1EF5 }
};

constexpr wchar_t V1[12][6] = {
    { 0x0041, 0x00C1, 0x00C0, 0x1EA2, 0x00C3, 0x1EA0 },
    { 0x0102, 0x1EAE, 0x1EB0, 0x1EB2, 0x1EB4, 0x1EB6 },
    { 0x00C2, 0x1EA4, 0x1EA6, 0x1EA8, 0x1EAA, 0x1EAC },
    { 0x0045, 0x00C9, 0x00C8, 0x1EBA, 0x1EBC, 0x1EB8 },
    { 0x00CA, 0x1EBE, 0x1EC0, 0x1EC2, 0x1EC4, 0x1EC6 },
    { 0x0049, 0x00CD, 0x00CC, 0x1EC8, 0x0128, 0x1ECA },
    { 0x004F, 0x00D3, 0x00D2, 0x1ECE, 0x00D5, 0x1ECC },
    { 0x00D4, 0x1ED0, 0x1ED2, 0x1ED4, 0x1ED6, 0x1ED8 },
    { 0x01A0, 0x1EDA, 0x1EDC, 0x1EDE, 0x1EE0, 0x1EE2 },
    { 0x0055, 0x00DA, 0x00D9, 0x1EE6, 0x0168, 0x1EE4 },
    { 0x01AF, 0x1EE8, 0x1EEA, 0x1EEC, 0x1EEE, 0x1EF0 },
    { 0x0059, 0x00DD, 0x1EF2, 0x1EF6, 0x1EF8, 0x1EF4 }
};

constexpr uint64_t fnv1aHash(const wchar_t *s, int len) {
    uint64_t h = 0xcbf29ce484222325ULL;
    for (int i = 0; i < len; ++i) {
        h ^= static_cast<uint64_t>(s[i]);
        h *= 0x100000001b3ULL;
    }
    return h;
}

template <size_t N>
bool hasSortedHash(const uint64_t (&arr)[N], uint64_t target) {
    size_t lo = 0, hi = N;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (arr[mid] == target) return true;
        if (arr[mid] < target) lo = mid + 1;
        else hi = mid;
    }
    return false;
}

constexpr uint64_t D0[27] = {
    0x08953e07b53f6f8aULL, 0x08953f07b53f713dULL, 0x08a25607b54a22aeULL, 0x08b35107b5588d62ULL, 0x08b35407b558927bULL, 0x08be3607b5626706ULL,
    0x08c83807b56abef1ULL, 0x08c83e07b56ac923ULL, 0x08d24f07b5733a8bULL, 0x08d54007b57556e5ULL, 0x213fba192577a7feULL, 0xaf63d94c8601e773ULL,
    0xaf63da4c8601e926ULL, 0xaf63de4c8601eff2ULL, 0xaf63df4c8601f1a5ULL, 0xaf63e04c8601f358ULL, 0xaf63e14c8601f50bULL, 0xaf63e34c8601f871ULL,
    0xaf63e54c8601fbd7ULL, 0xaf63e64c8601fd8aULL, 0xaf63e94c860202a3ULL, 0xaf63eb4c86020609ULL, 0xaf63ed4c8602096fULL, 0xaf63ee4c86020b22ULL,
    0xaf63ef4c86020cd5ULL, 0xaf63f54c86021707ULL, 0xcbf29ce484222325ULL
};

constexpr uint64_t D1[9] = {
    0x08a25607b54a22aeULL, 0x08b35107b5588d62ULL, 0x08b35407b558927bULL, 0xaf63de4c8601eff2ULL, 0xaf63e04c8601f358ULL, 0xaf63e34c8601f871ULL,
    0xaf63e94c860202a3ULL, 0xaf63ed4c8602096fULL, 0xcbf29ce484222325ULL
};

constexpr uint64_t D2[4] = {
    0x08a25607b54a22aeULL, 0xaf63de4c8601eff2ULL, 0xaf63e94c860202a3ULL, 0xaf63ed4c8602096fULL
};

constexpr uint64_t D3[6] = {
    0x08b35107b5588d62ULL, 0xaf63de4c8601eff2ULL, 0xaf63e04c8601f358ULL, 0xaf63e34c8601f871ULL, 0xaf63e94c860202a3ULL, 0xaf63ed4c8602096fULL
};

constexpr uint64_t D4[625] = {
    0x000e4b5f3607f485ULL, 0x0083c43b32948f2fULL, 0x0115f96c90d8cc99ULL, 0x01c099c5225d78f4ULL, 0x01e2260ecdeb3f05ULL, 0x021dc17a6f4f7bb2ULL,
    0x0264530b6aa5b24dULL, 0x0328d69d85be3076ULL, 0x0328d79d85be3229ULL, 0x0369250deb889a31ULL, 0x037e1a0deb9ae38aULL, 0x03a0240debb7daeeULL,
    0x03b10c0debc62559ULL, 0x03b1120debc62f8bULL, 0x03b1250debc64fd4ULL, 0x03b4300debc8985cULL, 0x0448dbad904c19c8ULL, 0x061ac44c9eec9a26ULL,
    0x067965832b3309acULL, 0x080f5619176d2878ULL, 0x087fdebb3c0a9fbaULL, 0x08cb4207b56d05c6ULL, 0x08cb4607b56d0c92ULL, 0x08cb4e07b56d1a2aULL,
    0x08cb5507b56d260fULL, 0x08cb5807b56d2b28ULL, 0x08cb5b07b56d3041ULL, 0x08cb5f07b56d370dULL, 0x09373c18bf59e8c9ULL, 0x095d4a18bf7acfd0ULL,
    0x0a25afff61b90e78ULL, 0x0a4e06cc5f6260aaULL, 0x0a80facc5f8da5dfULL, 0x0b0e7797342ee9c6ULL, 0x0b7a1e4bea695f89ULL, 0x0bb51791194b4414ULL,
    0x0bc60d911959a649ULL, 0x0bc60e911959a7fcULL, 0x0bcd1191195fcbc3ULL, 0x0bf2f59119806b6cULL, 0x0bf2fb911980759eULL, 0x0bf2fc9119807751ULL,
    0x0bf310911980994dULL, 0x0bf595a7a1aaec80ULL, 0x0c1e17f10ed69973ULL, 0x0c43c960f6d30fe6ULL, 0x0d1be7a2c400c080ULL, 0x0d1bf2a2c400d331ULL,
    0x0d3deba2c41dadb2ULL, 0x0d55f1a2c43249c5ULL, 0x0d5cfaa2c43877beULL, 0x0d5ff1a2c43a9e4aULL, 0x0e25dbd2b33b09d5ULL, 0x0e2f76719d468e74ULL,
    0x0f40ea29637fe28aULL, 0x0f40f029637fecbcULL, 0x0f40fa29637ffdbaULL, 0x0fdd06792894ff54ULL, 0x1001e27928b3de65ULL, 0x1001ea7928b3ebfdULL,
    0x1001f27928b3f995ULL, 0x10f0dd5dbbcf138fULL, 0x11b17b9125e871a8ULL, 0x11fb31ad5a1f35c4ULL, 0x11fb37ad5a1f3ff6ULL, 0x124955ad5a619441ULL,
    0x125f8a12243ad59cULL, 0x126583191dc1cb6bULL, 0x128a63908cbda375ULL, 0x12a978191dfb8586ULL, 0x12b5c14d3ebe54c2ULL, 0x13b4e4a7a5cc3c74ULL,
    0x1641a1c90d9840ecULL, 0x16db5bf43c472aa2ULL, 0x17cb038a3f618380ULL, 0x1885fc34ee003ba0ULL, 0x188a9e82d55da336ULL, 0x1a08981921ca3e19ULL,
    0x1a8b82ac20a4af82ULL, 0x1d108768e239eefcULL, 0x1dc74d9197537af0ULL, 0x1e3c75ef2e8ae673ULL, 0x1e5485ef2e9f9384ULL, 0x1e5c9130a426fa9dULL,
    0x1e65942e132f4f7aULL, 0x1f3758a2ce7b0c64ULL, 0x1f3b3fa2ce7ecac0ULL, 0x1f4247a2ce84f706ULL, 0x1f85be484dfda322ULL, 0x201db8e718237d75ULL,
    0x2057dd9771655b71ULL, 0x2098148ec99fb680ULL, 0x2118b4601e4231a7ULL, 0x21cde1e8e13cf0cfULL, 0x2281498aa0200e40ULL, 0x23ded0a6ec00cf9bULL,
    0x246ba30e3d002a93ULL, 0x248e65c2878db931ULL, 0x24b070ada2041cb0ULL, 0x26a4c90337eec619ULL, 0x27b9d0bdd83ac6d9ULL, 0x27d70f806be34523ULL,
    0x29263c8a882c99e5ULL, 0x2951474913e7a843ULL, 0x297a5749140ac887ULL, 0x2a207e12fc51cc05ULL, 0x2a7364019f7a95f0ULL, 0x2b32b0ab6f29b483ULL,
    0x2b719a8f4bb57213ULL, 0x2ba4ee5bae8b42e1ULL, 0x2bc202192bf1b3bdULL, 0x2bc24ea06dd61037ULL, 0x2bc8e7192bf7a48aULL, 0x2bcbf1192bf9eb5fULL,
    0x2bcc00192bfa04dcULL, 0x2bf127a332735e45ULL, 0x2c2d4d7605dec822ULL, 0x2c501a3949c24486ULL, 0x2cd86bbb511b8d79ULL, 0x2cfad118d3ecc02cULL,
    0x2cfad818d3eccc11ULL, 0x2cfada18d3eccf77ULL, 0x2cfae018d3ecd9a9ULL, 0x2d5ddc18d4415038ULL, 0x2e3aa0cc741845a0ULL, 0x2e3ab4cc7418679cULL,
    0x2f9e1731fe4a04d3ULL, 0x2fb517c354f4a9e7ULL, 0x2fbed1ef388301ddULL, 0x2fe0edef38a017d7ULL, 0x2fe3edef38a24daeULL, 0x2fe3f0ef38a252c7ULL,
    0x3009cbef38c2e325ULL, 0x3009d0ef38c2eba4ULL, 0x30bb947b3d7851c6ULL, 0x32ab7b2977c68a4bULL, 0x344e339bc2644eb8ULL, 0x365a2051cfca6664ULL,
    0x371fcfcb18769c1eULL, 0x374f828893a7023cULL, 0x375a952817412987ULL, 0x376e34638197a4a6ULL, 0x379d6b8893e8fc78ULL, 0x389aa8947e119beaULL,
    0x394c70f620b483e9ULL, 0x3a8bdbd8e17b835cULL, 0x3b28df7b43e00694ULL, 0x3be7fbbad14a09aaULL, 0x3c2f1bbad18642adULL, 0x3c3fde156cff1a83ULL,
    0x3c84c4e4a4da6497ULL, 0x3d5dd56be3296048ULL, 0x3d691ef619d96289ULL, 0x3d7002f619df51a3ULL, 0x3d80f0f619eda640ULL, 0x3d80fff619edbfbdULL,
    0x3db014f61a15542eULL, 0x3db3f1f61a19018cULL, 0x3e4bd4e31c5c3ad2ULL, 0x3edb2d9f264a6a80ULL, 0x3fd80475e188c550ULL, 0x4021d4aff04f740bULL,
    0x4033f5cc7e757b8aULL, 0x4077e7cc7eaf308cULL, 0x40b1d94aff3ab130ULL, 0x41804d728eb78f02ULL, 0x418338728eb9a12aULL, 0x41c171b52673603cULL,
    0x41e673b526927fdfULL, 0x42288471628c3333ULL, 0x42e6f0a2e2fd3fd6ULL, 0x43391a0572202ed4ULL, 0x4339ee8ab21c8380ULL, 0x4339fc8ab21c9b4aULL,
    0x436cf28ab247e3e5ULL, 0x4384e3f8c7cf18f1ULL, 0x43dc7cee246ba199ULL, 0x44ee4cad76b0aff6ULL, 0x44ee54ad76b0bd8eULL, 0x4544f751f0e763bcULL,
    0x472df8b834eacb1aULL, 0x484cd7c41eb765cdULL, 0x4930943c1f7a3dd5ULL, 0x4b27d7abbc423e59ULL, 0x4b499471c00a9e69ULL, 0x4bf8f99a73333900ULL,
    0x4c18079a734e0159ULL, 0x4c3fec8e0b8cfec5ULL, 0x4c4e8b193dc8be7eULL, 0x4c968190ace35550ULL, 0x4c968890ace36135ULL, 0x4c968a90ace3649bULL,
    0x4d0af94928725c68ULL, 0x4d1733c3b0b535f8ULL, 0x4db9cc461da79c7cULL, 0x4dcfa618e60201b4ULL, 0x4e0d857e6dc63cfcULL, 0x4e1fdb461dfe692bULL,
    0x4e248c18e64a1585ULL, 0x4e87258b2cd188abULL, 0x4f420c5e72f80f29ULL, 0x4f59ff5e730c8af3ULL, 0x4f5c4dd8e884633eULL, 0x4f75245e7323918aULL,
    0x4f941d5e733e3634ULL, 0x4f94a5db3fc39950ULL, 0x517eab08b2394165ULL, 0x536592566e7d862dULL, 0x53cdf835333a523fULL, 0x544438a7391e1e26ULL,
    0x549d2e0a493b08f5ULL, 0x5559658abc9ac26dULL, 0x556575c1ce107955ULL, 0x557e698abcb9e576ULL, 0x56d12ea086274034ULL, 0x585d7cd75cf6f848ULL,
    0x596b715935e2f5e7ULL, 0x5a73f1720ca645a3ULL, 0x5aa43849f8ed0f99ULL, 0x5ab3f9c9341f6c04ULL, 0x5b0f9c301b63c3ccULL, 0x5b5c98ef514dbfa5ULL,
    0x5c00877b55f7317cULL, 0x5c9b13ab81868553ULL, 0x5ca15824688fca91ULL, 0x5cad04a9f1a5d05dULL, 0x5e2cc5f62bdfe2b4ULL, 0x5e36bcf62be827eeULL,
    0x5e3995f62bea1b80ULL, 0x5e3996f62bea1d33ULL, 0x5e399df62bea2918ULL, 0x5e39a0f62bea2e31ULL, 0x5e39aaf62bea3f2fULL, 0x5e76bbf62c1e0a30ULL,
    0x5e76c2f62c1e1615ULL, 0x5e7da6f62c24052fULL, 0x5e81a4f62c27eaa0ULL, 0x5e87c9f62c2c952dULL, 0x5ea0e11948721ef1ULL, 0x5eade919487cb6e5ULL,
    0x5eadee19487cbf64ULL, 0x5eadef19487cc117ULL, 0x5ec5ea1948914a79ULL, 0x5ec5fc194891690fULL, 0x5ec9dd1948951d39ULL, 0x5fe81a12c70cd56eULL,
    0x5feded18f07e3c11ULL, 0x600e2845cc70f20aULL, 0x6016dd18f0a125f5ULL, 0x602d98206ddb2d19ULL, 0x602ed118f0b5a372ULL, 0x60eff27ea8f2ee03ULL,
    0x62302200658996b7ULL, 0x62e08cf6d262e733ULL, 0x62e0a6f6d2631361ULL, 0x647b86132a678189ULL, 0x6498d3e4855b9f43ULL, 0x6606b7cd977073c2ULL,
    0x6675e27edfa85d49ULL, 0x67189dd52a79e0c0ULL, 0x6727e771efac7b4cULL, 0x673ebb0102773a20ULL, 0x6741cf01027991f3ULL, 0x675aff71efd7fdadULL,
    0x67604bab88388faeULL, 0x68fbbff88ee6fed0ULL, 0x6931f45bd1aabcacULL, 0x69f800801812a5f0ULL, 0x69faf6a8ba9fee96ULL, 0x6a61b5fbb6da2b4bULL,
    0x6a61b6fbb6da2cfeULL, 0x6b8b97abcdf6a17bULL, 0x6be6f4bd63ee5928ULL, 0x6c75180e275861c7ULL, 0x6c7c120e275e7643ULL, 0x6da6061fd1e081bdULL,
    0x6dcf151fd203a04eULL, 0x6de0021fd211f338ULL, 0x6dec8f493a91bd3fULL, 0x6e308c493acb84f2ULL, 0x6e308e493acb8858ULL, 0x6e30a3493acbac07ULL,
    0x6e89a70865f1fedcULL, 0x6f3fb3842ffa02bbULL, 0x6f4743b8bc5b4eb2ULL, 0x7058edf6366825c0ULL, 0x7058f2f636682e3fULL, 0x7058f3f636682ff2ULL,
    0x7058fbf636683d8aULL, 0x7058fcf636683f3dULL, 0x707e16f6368787a8ULL, 0x712d43a22ec5c2d6ULL, 0x712d44a22ec5c489ULL, 0x712d49a22ec5cd08ULL,
    0x719976c1aba8671eULL, 0x71f304ea62c01cbdULL, 0x726bacc28784af92ULL, 0x7271c68759916228ULL, 0x73190dcc9afab347ULL, 0x74e4551cece4e7d6ULL,
    0x75f4609b951ac55bULL, 0x76bd7abd8908c711ULL, 0x7708e18434236f21ULL, 0x779b5a19564f32b6ULL, 0x779b5b19564f3469ULL, 0x77a8ebde485fc25fULL,
    0x77af6419565fecbeULL, 0x77ca6b195676c05bULL, 0x7884f79b0c364646ULL, 0x79df625b5bb48798ULL, 0x7a665fdb3d9f1cfcULL, 0x7aa8ee5e8b93b862ULL,
    0x7c96deb4c28468f1ULL, 0x7ce4fd9430e80ceaULL, 0x7d0cfe94310960b1ULL, 0x7d2fed72e064ffd2ULL, 0x7d6780e4032b48f2ULL, 0x7f189dd0bc4902cbULL,
    0x7f2c53536a7aab3cULL, 0x7f625478d788e11bULL, 0x80fc80cc11f77ff8ULL, 0x816995a82874c838ULL, 0x822d98195cd5edaaULL, 0x8248a1195cecc4adULL,
    0x824f97195cf2d25dULL, 0x827f84195d1bd5d6ULL, 0x8296168289c4e8f9ULL, 0x8312e876372a66caULL, 0x8370737adb4d000fULL, 0x83cf8e8f9081468bULL,
    0x855b516730a34339ULL, 0x855b556730a34a05ULL, 0x8561566730a7b766ULL, 0x85615b6730a7bfe5ULL, 0x85615d6730a7c34bULL, 0x85616c6730a7dcc8ULL,
    0x869a82ef69c67162ULL, 0x876819f3dc3d9993ULL, 0x885730a4aa4739a9ULL, 0x893985bfa8d403a0ULL, 0x899befe89b8fb478ULL, 0x89b5d67f99520fc6ULL,
    0x89d7ed7f996f1d41ULL, 0x89f6c11960ff5191ULL, 0x8b07644672a64103ULL, 0x8baac32f65bd97e8ULL, 0x8be4c62929b73271ULL, 0x8c22ef0da88b0d1dULL,
    0x8c22f10da88b1083ULL, 0x8c2cdb0da8933fa6ULL, 0x8c2cf10da8936508ULL, 0x8c2cf60da8936d87ULL, 0x8c2fd80da8957064ULL, 0x8c2fe90da8958d47ULL,
    0x8c3e28b39fdae2c4ULL, 0x8c5db72275346f4dULL, 0x8ddc723ce256bf99ULL, 0x8e49878dc25c8affULL, 0x8e50e547fef6fce7ULL, 0x8f0d65f748da41c4ULL,
    0x8fcf8bbd78a0502eULL, 0x8fe063ff7e501d70ULL, 0x904a6a85be6ab263ULL, 0x9071590e7163daecULL, 0x91790f9ec40c3f01ULL, 0x92712064aad3aee1ULL,
    0x92d2aa208a2a76afULL, 0x9336e4b8d1137564ULL, 0x93c4681debd27211ULL, 0x94409ad0d8099610ULL, 0x991cd6779b15a35cULL, 0x9a79f79baa52b203ULL,
    0x9a7a059baa52c9cdULL, 0x9a7ce19baa54c278ULL, 0x9bd4c0f64f161186ULL, 0x9be8c5f64f26c30fULL, 0x9bf6bff64f32f639ULL, 0x9c9327fff79474acULL,
    0x9ce4d6720e9c9118ULL, 0x9d06e5720eb990fbULL, 0x9d2cfb720eda859aULL, 0xa03a74a942db43bdULL, 0xa0eff7498c7eb219ULL, 0xa0effd498c7ebc4bULL,
    0xa0f367d5a5c6e876ULL, 0xa12d0c41c86ad47eULL, 0xa1a9a8be7af7d8faULL, 0xa354fd1ff0c467c5ULL, 0xa39d8fc6921fbf94ULL, 0xa3b3ec1ff114df66ULL,
    0xa41635a24b4ea2d8ULL, 0xa474ed41efa4a938ULL, 0xa47809ae5cba1648ULL, 0xa4ba9dc3e19eb3b3ULL, 0xa514b5c2a3d7d2b4ULL, 0xa5b762ec3b89fc48ULL,
    0xa5c90667425fe82fULL, 0xa6190af6555abf8dULL, 0xa6200df65560e354ULL, 0xa6200ef65560e507ULL, 0xa6200ff65560e6baULL, 0xa66b06f655a0c2e9ULL,
    0xa67c04f655af32b6ULL, 0xa67c11f655af48cdULL, 0xa67eedf655b14178ULL, 0xa6ee9c8395864ea3ULL, 0xa7201178677596c9ULL, 0xa73288764c0baf8bULL,
    0xa79439ef7bfa9c2dULL, 0xa90e61c464fa89c3ULL, 0xaa6973780845fdb2ULL, 0xaa77f578efdfc4b9ULL, 0xaa77fd78efdfd251ULL, 0xaa7b1278efe22bd7ULL,
    0xaabe362250e8c5eeULL, 0xaac23fe3c6b92b12ULL, 0xaad01178f02a6a23ULL, 0xab47b25ddd5ff2d8ULL, 0xac09659fa3d48bfaULL, 0xad703dbfbdc8540aULL,
    0xadae49645df2840bULL, 0xaeae7e0db2d760cfULL, 0xaf064559c385d45fULL, 0xb0577b29135f0bb1ULL, 0xb19121adf2757487ULL, 0xb19416adf27797adULL,
    0xb1a1e28e443fd5a8ULL, 0xb430d2537a2e6ce8ULL, 0xb4fe870860494a5cULL, 0xb55e6190e8792fd1ULL, 0xb55e6590e879369dULL, 0xb5614d90e87b43acULL,
    0xb5614e90e87b455fULL, 0xb5615a90e87b59c3ULL, 0xb5615e90e87b608fULL, 0xb5fae2c14238b978ULL, 0xb62e276d65369684ULL, 0xb69a62192199d4e0ULL,
    0xb82a5f411851c1cbULL, 0xb91f4d3050522d99ULL, 0xb93a12b0d06caefcULL, 0xba0f6b77ad4375b3ULL, 0xba8821b572531e29ULL, 0xba9c07331551f52aULL,
    0xba9f133315543f65ULL, 0xbb0ecd6aede4a10cULL, 0xbb60db445fbf5155ULL, 0xbb62c62c9808ea37ULL, 0xbb7acfefaad7b3baULL, 0xbc0b737ce965a2b7ULL,
    0xbc8e191648d2669fULL, 0xbe2aa1bf4c0cd8a7ULL, 0xbf3084ad6938593cULL, 0xbf30d40dc532f345ULL, 0xc02f4afe8a9e2523ULL, 0xc0dc534e3003c89bULL,
    0xc10e63fbe7f624f5ULL, 0xc10e68fbe7f62d74ULL, 0xc1347ec95cfd99ccULL, 0xc22cc76c12e7e854ULL, 0xc36a8b51a75fc34cULL, 0xc3780d35723576efULL,
    0xc3ac1a5d82cffd39ULL, 0xc3c3013572754e05ULL, 0xc3c7338e4ec23fb1ULL, 0xc463d5ba8e1736a8ULL, 0xc4f7c7a25d6dfce3ULL, 0xc4f7cba25d6e03afULL,
    0xc52ce191058747eaULL, 0xc5c7b983377cad5fULL, 0xc653fd0dc8cfc005ULL, 0xc6decaecfda8f056ULL, 0xc6f4383a69638175ULL, 0xc771fca99beaeafdULL,
    0xc82968bce6f3c054ULL, 0xc8bf1e4663d4aafaULL, 0xca40a467578ba360ULL, 0xca40b567578bc043ULL, 0xca449b67578f7cecULL, 0xcab5878ca7e142efULL,
    0xcaf63635761eef5cULL, 0xcb8ce71d1dfcc915ULL, 0xcb9c2ff074357472ULL, 0xcc3fbeffa766c129ULL, 0xcca1a5e598127a88ULL, 0xccbd06aa30f787f6ULL,
    0xcd0d5484ba43aa8eULL, 0xcd1ec79bc6a18b73ULL, 0xcd2fcd9bc6b008d8ULL, 0xcd2fdc9bc6b02255ULL, 0xcd81eaac9e8d33afULL, 0xcdece4ad70d57debULL,
    0xcdecedad70d58d36ULL, 0xce03eaad70e866feULL, 0xce47faad71224efaULL, 0xce87a3885811296eULL, 0xce989e88581f9422ULL, 0xceadb82265a0b7f3ULL,
    0xced973885856e206ULL, 0xcfec48b2e070d298ULL, 0xcfece6722b4054a3ULL, 0xcff61d7d1f7b0d70ULL, 0xcffd4db2e07f4e4aULL, 0xd0013bb2e083188bULL,
    0xd015ce722b6330efULL, 0xd061426f9c9a1c85ULL, 0xd2e952a95f32897cULL, 0xd3b5e34c82d387c8ULL, 0xd3cacd4c82e5be70ULL, 0xd4c906d06b5581dcULL,
    0xd51687bec34aff71ULL, 0xd52e23a5083356c2ULL, 0xd5e5dd79088196d2ULL, 0xd61bdd7908af2642ULL, 0xd7dc3f51106bd11bULL, 0xd88061d4eab33056ULL,
    0xd89aa06245afb2beULL, 0xd95d50ef07a74024ULL, 0xda4e07a2a78ec6ccULL, 0xda5900a2a798c26cULL, 0xda590fa2a798dbe9ULL, 0xdb40b887952d79edULL,
    0xdb4717b414fefae5ULL, 0xdbf021fa49d5d29fULL, 0xdc11e76761c768a0ULL, 0xdc22d9e0df2d1cfbULL, 0xdc33f56761e466d0ULL, 0xdc55ef6762014304ULL,
    0xdc55f66762014ee9ULL, 0xdc9e7e18fec93bb8ULL, 0xdcb28218fed9eb8eULL, 0xdcb97e18fee00370ULL, 0xdcc68b18feeaa3e3ULL, 0xdd11fc790c24f419ULL,
    0xdd120c790c250f49ULL, 0xdd1214790c251ce1ULL, 0xdd1cf6790c2ef16cULL, 0xdd1d06790c2f0c9cULL, 0xdd1d0d790c2f1881ULL, 0xdd1d0f790c2f1be7ULL,
    0xdd6bb50275ff38ceULL, 0xdd7b4418e9ef7550ULL, 0xdeb23f9bd0a849a4ULL, 0xdec59ea6c4eb9aeeULL, 0xdeec1c9bd0d98672ULL, 0xdf2d3c48badab5b6ULL,
    0xdfc46c0dd7103631ULL, 0xdfc4700dd7103cfdULL, 0xdfd2700dd71c7a59ULL, 0xdff7680dd73b88feULL, 0xdff76b0dd73b8e17ULL, 0xdff7710dd73b9849ULL,
    0xe0ede18862cb0a23ULL, 0xe1b2505a044b0eb4ULL, 0xe1d82b6293801d10ULL, 0xe2078c6d17943560ULL, 0xe2776d7d7e4f5780ULL, 0xe38acbdfbd0ee0c8ULL,
    0xe5316cbaa025f028ULL, 0xe5660aeee07403d0ULL, 0xe57882baa062182dULL, 0xe59367ea12bc61ccULL, 0xe5bfe30361234b02ULL, 0xe745ad1905623939ULL,
    0xe745b219056241b8ULL, 0xe756b7190570bd6aULL, 0xe7719fd4d051bc35ULL, 0xe77cdeafb40bdc7cULL, 0xe7f9e48bf5652f03ULL, 0xe8496efeb5f4f365ULL,
    0xe92047870c268d5bULL, 0xe9628acaca9c7d82ULL, 0xeadd6394f6b31a63ULL, 0xeaf55eddf815959fULL, 0xeb17ad725dd579eeULL, 0xeb2a39e5ed4703c2ULL,
    0xeb5b1d96125267abULL, 0xebddd46117f69692ULL, 0xebe90009bda2153cULL, 0xedb2d39755161f73ULL, 0xee5d97ad45ad251fULL, 0xee5da6ad45ad3e9cULL,
    0xeef04f104476752cULL, 0xef2359791696c97cULL, 0xef56457916c20119ULL, 0xef564d7916c20eb1ULL, 0xef5a4a7916c5f26fULL, 0xf04f35ae761bd424ULL,
    0xf212577d0893de4cULL, 0xf39577723fbc5d82ULL, 0xf3b36f723fd54d79ULL, 0xf3d584723ff2578eULL, 0xf479a5e48538d177ULL, 0xf4cd65eb4aa3fd61ULL,
    0xf4d30088534a1af4ULL, 0xf571f19544dee8b2ULL, 0xf5fdf5190cfb4c49ULL, 0xf60507190d01898dULL, 0xf6804f48f7734ff0ULL, 0xf6914448f781b072ULL,
    0xf6915548f781cd55ULL, 0xf7483fb265b60ad2ULL, 0xf775f8a97470ae4fULL, 0xf79a102f6f885c2fULL, 0xf7e910fde4ac55e0ULL, 0xf7e91bfde4ac6891ULL,
    0xf83e67ffb98b9914ULL, 0xf89e75bdb43c5a5bULL, 0xf8a5beb420205440ULL, 0xf8bb5018d44450caULL, 0xf9393d95a0b481f2ULL, 0xf96ca0246daa2be9ULL,
    0xf9b9ee78053379f4ULL, 0xfa04f4ef1995407eULL, 0xfaee29cefe6c62c7ULL, 0xfd3bab7bd23f9c9bULL, 0xfd6f0e4e166f85bcULL, 0xfd915c894f4b46bcULL,
    0xfe43e600c6b618b7ULL, 0xfe46f400c6b86658ULL, 0xfeeecd55440ac3f3ULL, 0xff75d19be2aea620ULL, 0xff75de9be2aebc37ULL, 0xff89db9be2bf6028ULL,
    0xffcd24a6d72bafd2ULL
};

constexpr uint64_t D5[371] = {
    0x002b0f19132cc9dfULL, 0x002b1d19132ce1a9ULL, 0x003934191339461aULL, 0x004d2e191349e4f2ULL, 0x004d31191349ea0bULL, 0x004d35191349f0d7ULL,
    0x00542519134ff455ULL, 0x00611d19135a7119ULL, 0x00613019135a9162ULL, 0x03b42b0debc88fddULL, 0x0442d3ad9047a082ULL, 0x0448c8ad904bf97fULL,
    0x044ce3ad90501037ULL, 0x0456d2ad905847d9ULL, 0x0460cbad90609079ULL, 0x0464cbad90647950ULL, 0x07e64e19174a15ccULL, 0x07f4461917564590ULL,
    0x07f4511917565841ULL, 0x08084e191766fc32ULL, 0x080f5119176d1ff9ULL, 0x080f5719176d2a2bULL, 0x081d4e191779583cULL, 0x08915907b53bb494ULL,
    0x08953907b53f670bULL, 0x089c3707b5458253ULL, 0x089c3807b5458406ULL, 0x089c4e07b545a968ULL, 0x089c5507b545b54dULL, 0x08a62f07b54dc940ULL,
    0x08a64b07b54df8d4ULL, 0x08a94307b5502113ULL, 0x08a95f07b55050a7ULL, 0x08b05407b5565ca4ULL, 0x08b05507b5565e57ULL, 0x08b05807b5566370ULL,
    0x08b06007b5567108ULL, 0x08b35907b5589afaULL, 0x08b73007b55c3e26ULL, 0x08b73807b55c4bbeULL, 0x08b73e07b55c55f0ULL, 0x08b74507b55c61d5ULL,
    0x08ba5307b55eaf76ULL, 0x08c43a07b566d980ULL, 0x08c43d07b566de99ULL, 0x08c83907b56ac0a4ULL, 0x08cb4307b56d0779ULL, 0x08cb4407b56d092cULL,
    0x08cb4507b56d0adfULL, 0x08cb5307b56d22a9ULL, 0x08cb5707b56d2975ULL, 0x08d93907b57933d7ULL, 0x09823c18bf99d443ULL, 0x09854418bf9c17b2ULL,
    0x0a4dfbcc5f624df9ULL, 0x0a4e01cc5f62582bULL, 0x0a8110cc5f8dcb41ULL, 0x0bc9fa91195d6ed7ULL, 0x0bca0591195d8188ULL, 0x0bef0691197c9f78ULL,
    0x0bf2f29119806653ULL, 0x0bf30d9119809434ULL, 0x0c519da7a1f958c5ULL, 0x0d18faa2c3feaaf2ULL, 0x0d5605a2c4326bc1ULL, 0x0d5cf0a2c43866c0ULL,
    0x0f136ff2c086b760ULL, 0x119805b47155934eULL, 0x124a77191daaef4fULL, 0x125083191daf6f61ULL, 0x125087191daf762dULL, 0x127275191dcc3dfdULL,
    0x12727f191dcc4efbULL, 0x12a97f191dfb916bULL, 0x14812a75c8f9e9e2ULL, 0x15e2c4b6ec0964b8ULL, 0x180a95484a16608cULL, 0x19f1951921b75a1fULL,
    0x1a2e981921eb0d56ULL, 0x1a2e991921eb0f09ULL, 0x1c997666f511dce5ULL, 0x1dd35cf2f7a7cc41ULL, 0x1e359bef2e850857ULL, 0x1e4393ef2e91381bULL,
    0x1e4983ef2e958899ULL, 0x1e5493ef2e9fab4eULL, 0x1f234fa2ce6a540fULL, 0x1f3b51a2ce7ee956ULL, 0x1f3b57a2ce7ef388ULL, 0x1f4f5fa2ce8faa2aULL,
    0x1f594fa2ce97e37fULL, 0x1f645fa2cea20634ULL, 0x2138d9192571bdfdULL, 0x215ad019258e9518ULL, 0x215ad119258e96cbULL, 0x215ad519258e9d97ULL,
    0x249587ada1ed7c0dULL, 0x249887ada1efb1e4ULL, 0x24ba88ada20c99fdULL, 0x24ed7fada237e44bULL, 0x2543c4ef320f790dULL, 0x2579c4ef323d087dULL,
    0x2579ceef323d197bULL, 0x2587bcef32493841ULL, 0x268dd90337dc0268ULL, 0x2ba002192bd4cd57ULL, 0x2ba00d192bd4e008ULL, 0x2bb3ea192be54d99ULL,
    0x2bc8dc192bf791d9ULL, 0x2bc8ea192bf7a9a3ULL, 0x2bcbed192bf9e493ULL, 0x2c2a297605dc551fULL, 0x2c37327605e6eec6ULL, 0x2c743776061aa563ULL,
    0x2c824e76062709d4ULL, 0x2cfadb18d3ecd12aULL, 0x2cfadf18d3ecd7f6ULL, 0x2d0a7f6108dbdf65ULL, 0x2d34e018d41e51f0ULL, 0x2e29a4cc7409d939ULL,
    0x2e2cabcc740c1af5ULL, 0x2e36bbcc74148aaaULL, 0x2e3abdcc741876e7ULL, 0x2e4ea3cc7428f3c3ULL, 0x2e5fa3cc743766f6ULL, 0x2efdb9b6c7ecb4fcULL,
    0x2fc1d5ef38853e80ULL, 0x2fc1d6ef38854033ULL, 0x2fdde5ef389dd468ULL, 0x2fffd2ef38ba9a85ULL, 0x3002edef38bcfe3dULL, 0x3176de00e37d3b65ULL,
    0x3288a6840d9037f4ULL, 0x334a1a192fe363ccULL, 0x334a1b192fe3657fULL, 0x335f27192ff5d5edULL, 0x337323193006782bULL, 0x3ac5dd51ea6fdbfeULL,
    0x3be50fbad147f5cfULL, 0x3c0d0dbad169447dULL, 0x3c10f2bad16cff73ULL, 0x3dd64c1936659eaeULL, 0x4073f0cc7eab5700ULL, 0x4077f8cc7eaf4d6fULL,
    0x423f491cd095a872ULL, 0x42fefba2e311e468ULL, 0x4313541d504f4163ULL, 0x4326f1a2e333257eULL, 0x43523a00edc17fa5ULL, 0x43552b00edc39bffULL,
    0x437b2800ede46623ULL, 0x43f026556b0ba904ULL, 0x4a4e627d65155002ULL, 0x4c488e193dc457e9ULL, 0x4c4e90193dc8c6fdULL, 0x4c4e92193dc8ca63ULL,
    0x4c529f193dccc951ULL, 0x4c52ac193dccdf68ULL, 0x4c52ae193dcce2ceULL, 0x4c637f90acb7f851ULL, 0x4c816f90acd0dab0ULL, 0x4c8f8790acdd40d4ULL,
    0x4caa96193e172fdcULL, 0x4cb66f1fbfb4e1d7ULL, 0x4cf3611fbfe8782bULL, 0x4cf3741fbfe89874ULL, 0x4cf3751fbfe89a27ULL, 0x4d907a1e866d3a84ULL,
    0x4dd1d3461dbc3a42ULL, 0x4e028c18e62d2f1fULL, 0x5049a1312aa2506fULL, 0x51f1a6035075521bULL, 0x56d7be194448c53cULL, 0x56d7c8194448d63aULL,
    0x56e4b719445343b3ULL, 0x56e4c019445352feULL, 0x56e4cd1944536915ULL, 0x56f2cf19445fa9d7ULL, 0x56f9b319446598f1ULL, 0x56f9bf194465ad55ULL,
    0x571bb71944828623ULL, 0x5728cf19448d3947ULL, 0x584c7fd75ce88a2eULL, 0x585d6ad75cf6d9b2ULL, 0x585dfbb29d3568ccULL, 0x587602b29d4a0692ULL,
    0x5b25b8ef511eb395ULL, 0x5beddbba52c73a21ULL, 0x5e39abf62bea40e2ULL, 0x5eade819487cb532ULL, 0x6016c818f0a10246ULL, 0x6031e618f0b7fcf8ULL,
    0x624c45762521b794ULL, 0x66f6cc010239a160ULL, 0x6717d2465dee33ceULL, 0x68e909194eba7c09ULL, 0x690418194ed15d3eULL, 0x690419194ed15ef1ULL,
    0x691210194edd8d02ULL, 0x691211194edd8eb5ULL, 0x6bac3f48789bd617ULL, 0x6d87181fd1c5efc4ULL, 0x6d91101fd1ce36b1ULL, 0x6db0001fd1e8cc10ULL,
    0x6db3081fd1eb0f7fULL, 0x731d02cc9afe896dULL, 0x732dfbcc9b0cf0bbULL, 0x758cca0a5b66b15aULL, 0x75f4549b951ab0f7ULL, 0x75f4589b951ab7c3ULL,
    0x76134b9b9535523bULL, 0x76244e9b9543ca87ULL, 0x77bc7219566a8ee4ULL, 0x77bc8119566aa861ULL, 0x77ca6a195676bea8ULL, 0x7f864360a6809a86ULL,
    0x81be7a693057527eULL, 0x822d94195cd5e6deULL, 0x823b76195ce1f140ULL, 0x823b8d195ce21855ULL, 0x823b93195ce22287ULL, 0x824885195cec9519ULL,
    0x82488b195cec9f4bULL, 0x82718c195d0fa612ULL, 0x82718d195d0fa7c5ULL, 0x82d5d67636f69a16ULL, 0x8338e976374b37baULL, 0x8355827adb3651d4ULL,
    0x85577867309f9ca7ULL, 0x8587736730c8b7eaULL, 0x85a56b6730e1a7e1ULL, 0x85b05b6730eb9436ULL, 0x869a8aef69c67efaULL, 0x88d9415e5c57ae90ULL,
    0x891638843e91517bULL, 0x893530843eabf472ULL, 0x89b2ad1960c562c9ULL, 0x89e9ad1960f4a539ULL, 0x89e9c01960f4c582ULL, 0x89f6c51960ff585dULL,
    0x8a0bc1196111ad9bULL, 0x8a11b519611604e5ULL, 0x8b069b7204564f14ULL, 0x8b0d9172045c5cc4ULL, 0x8b1e8b72046ac5c5ULL, 0x8c39b3a72739dd55ULL,
    0x9a1ae79baa02024fULL, 0x9a79ef9baa52a46bULL, 0x9a79fa9baa52b71cULL, 0xa351f61ff0c22609ULL, 0xa3550b1ff0c47f8fULL, 0xa355141ff0c48edaULL,
    0xa35c061ff0ca95beULL, 0xa3a7061ff10a8138ULL, 0xa3b3f01ff114e632ULL, 0xa5c90867425feb95ULL, 0xa7328f764c0bbb70ULL, 0xa73c7d764c13f15fULL,
    0xa74085764c17e7ceULL, 0xa7438c764c1a298aULL, 0xaa4651f3183a4800ULL, 0xab9d797d0a69f89cULL, 0xabaa89c7b453255fULL, 0xabb498c7b45b9361ULL,
    0xb0e7a6146c2b0d49ULL, 0xb109a0146c47e97dULL, 0xb1b60fadf294722eULL, 0xb258581ff89d8698ULL, 0xb3f5f1b6b3d271c0ULL, 0xb48882f31e7e48b5ULL,
    0xb5137390e83962edULL, 0xb51a7a1979629b53ULL, 0xb51d6390e8419c42ULL, 0xb55a6b90e87557f8ULL, 0xb55e7090e879494eULL, 0xb5615b90e87b5b76ULL,
    0xb5686390e88187bcULL, 0xb66c6ca292e2e7a8ULL, 0xb69a65192199d9f9ULL, 0xb6de701921d3b976ULL, 0xb8ff65e228006d51ULL, 0xb92b6ce22825b421ULL,
    0xbc1f81c24c4400baULL, 0xbf062ab6bac46948ULL, 0xbf0bcc0dc513c970ULL, 0xbf778dad69746b2aULL, 0xbf779aad69748141ULL, 0xbf7b83ad69784303ULL,
    0xbfbdb3197ff7c0fbULL, 0xbfeddc1f6f584edbULL, 0xbffedf1f6f66c727ULL, 0xc0869a7afe078b88ULL, 0xc2ec0618f04f6c4cULL, 0xc2f00e18f05362bbULL,
    0xc2f31618f055a62aULL, 0xc3011118f061db07ULL, 0xc49b73b3cd190edaULL, 0xc4ac6eb3cd27798eULL, 0xc4bcbfba8e633a1cULL, 0xc61cfd0dc8a07d95ULL,
    0xc9ebb36757437cdeULL, 0xca030c724b8aaccdULL, 0xca44aa67578f9669ULL, 0xca4a04724bc6a1d8ULL, 0xca9a1a18f461e4ccULL, 0xca9a1d18f461e9e5ULL,
    0xca9a2618f461f930ULL, 0xca9a2718f461fae3ULL, 0xcaa83e18f46e5f54ULL, 0xcaa83f18f46e6107ULL, 0xcaaf2b18f4745db9ULL, 0xcaaf2f18f4746485ULL,
    0xccdac5b44a8ea584ULL, 0xcd1ed09bc6a19abeULL, 0xcd2bd59bc6ac2d99ULL, 0xcd2fd39bc6b0130aULL, 0xce00e5ad70e628a8ULL, 0xce33e5ad71118241ULL,
    0xce4bd7ad7125fc58ULL, 0xce4be8ad7126193bULL, 0xce9e648e5584645aULL, 0xd14e19ec544e8032ULL, 0xd4f05818fab6a4a2ULL, 0xd50b6818facd878aULL,
    0xd50b7518facd9da1ULL, 0xd9344bef07843291ULL, 0xd97f55ef07c42f09ULL, 0xda2907a2a76faa8fULL, 0xdc04126761bb7455ULL, 0xdc47fd6761f51d72ULL,
    0xdc4f056761fb49b8ULL, 0xdc520d6761fd8d27ULL, 0xdd75b181e12fd660ULL, 0xdec33f9bd0b6bcd7ULL, 0xdecf88a6c4f3ca11ULL, 0xded7279bd0c73d19ULL,
    0xdee54148ba9d0892ULL, 0xdfbd880dd70a4717ULL, 0xdfc8770dd71431b9ULL, 0xe387b9dfbd0c8c5bULL, 0xe5566ebaa0450fcbULL, 0xe5646bbaa051480eULL,
    0xe5786cbaa061f2cbULL, 0xe6f3a219051c1c60ULL, 0xe6f7aa19052012cfULL, 0xe701ba1905288284ULL, 0xe701bb1905288437ULL, 0xe70c0bb730c98252ULL,
    0xe756c0190570ccb5ULL, 0xe7599f190572ca79ULL, 0xe759b9190572f6a7ULL, 0xeaee9e725db25b5dULL, 0xeaf1ba725db4c0c8ULL, 0xeb13a9725dd18a4bULL,
    0xef7a8bd7214a392cULL, 0xf1af21b6d7176dd4ULL, 0xf2737a910b31f080ULL, 0xf28882910b445a22ULL, 0xf2958f910b4efa95ULL, 0xf2a393910b5b3ebdULL,
    0xf5b9fc190cc18b62ULL, 0xf5e305190ce49fc1ULL, 0xf604f8190d017010ULL, 0xf604fc190d0176dcULL, 0xf9e3d9ef1979df37ULL, 0xf9e6e6ef197c2b25ULL,
    0xfa31fcef19bc3c01ULL, 0xfe38e000c6ac0700ULL, 0xfe76de00c6e164b8ULL, 0xff71c69be2aaaa98ULL, 0xffe124a6d73c58dcULL
};

constexpr uint64_t D6[49] = {
    0x00611e19135a72ccULL, 0x08915907b53bb494ULL, 0x08953907b53f670bULL, 0x089c4e07b545a968ULL, 0x08a62f07b54dc940ULL, 0x08a64b07b54df8d4ULL,
    0x08a94307b5502113ULL, 0x08b05807b5566370ULL, 0x08b73807b55c4bbeULL, 0x08b73e07b55c55f0ULL, 0x08b74507b55c61d5ULL, 0x08ba5307b55eaf76ULL,
    0x08c83907b56ac0a4ULL, 0x08cb5307b56d22a9ULL, 0x09a13e18bfb48838ULL, 0x19f7991921bbcc99ULL, 0x1f5359a2ce9388cfULL, 0x215ad619258e9f4aULL,
    0x256cadef3232570cULL, 0x2579baef323cf77fULL, 0x2587bcef32493841ULL, 0x2e47c5cc74230edbULL, 0x334a1a192fe363ccULL, 0x335808192fef8292ULL,
    0x335813192fef9543ULL, 0x337323193006782bULL, 0x3db3f1f61a19018cULL, 0x3f74142d6181ea7eULL, 0x418338728eb9a12aULL, 0x56f5c9194461d57cULL,
    0x5eade819487cb532ULL, 0x75f4589b951ab7c3ULL, 0x7f845078d7a5c0b5ULL, 0x8245aa195cea9e21ULL, 0xa6190af6555abf8dULL, 0xa66b06f655a0c2e9ULL,
    0xac85085e70d64908ULL, 0xb5617c19799ea15cULL, 0xd3470d49a88be12aULL, 0xd4e26318faaa79f7ULL, 0xd94551ef0792aff6ULL, 0xdcb27818fed9da90ULL,
    0xe6f79719051ff286ULL, 0xe756c8190570da4dULL, 0xeaf1ba725db4c0c8ULL, 0xeb06b1725dc70d87ULL, 0xee63aaad45b1b116ULL, 0xf5a6c8c57a9061a3ULL,
    0xf5e2f1190ce47dc5ULL
};

constexpr uint64_t D7[23] = {
    0x04cc0fca18a01d8fULL, 0x097b5e18bf93ef5bULL, 0x09a13e18bfb48838ULL, 0x13732296e2a2884aULL, 0x137b2d911d7251dbULL, 0x1923443d4dbc1fd7ULL,
    0x2e47c5cc74230edbULL, 0x335808192fef8292ULL, 0x3b0318082dc133f4ULL, 0x3f74142d6181ea7eULL, 0x4250e178a55e5478ULL, 0x44112fcef1621e49ULL,
    0x58915199d84d2874ULL, 0x5ea0e11948721ef1ULL, 0x9c68c3ffbacc25dcULL, 0xb9681c544ae50e88ULL, 0xc36a8b51a75fc34cULL, 0xc61cef0dc8a065cbULL,
    0xcd63ec99754aab0dULL, 0xe391ac8f9339a328ULL, 0xe41deb4b60037d24ULL, 0xe61547b458a1ac89ULL, 0xf9a16f18fb4700d6ULL
};

constexpr uint64_t D8[29] = {
    0x080f6019176d3976ULL, 0x088e3707b53944f7ULL, 0x08a1cf07b5493d49ULL, 0x08a3bb07b5384b2eULL, 0x08a3eb07b549efb4ULL, 0x08b3bd07b55944e6ULL,
    0x08c82f07b56aafa6ULL, 0x14338a191f4a3388ULL, 0x21447d19257715dcULL, 0x33580d192fef8b11ULL, 0x48438a91541ab070ULL, 0x48c41ba52a0c86faULL,
    0x4ca9181377c52c76ULL, 0x504ac78c26f7c02eULL, 0x556bd51943135a74ULL, 0x61e55208012073feULL, 0x9b1789ad4a8c9732ULL, 0xa5258f197a8c0285ULL,
    0xa6f50419837164f8ULL, 0xaf7e924c862f4fceULL, 0xe6f7a319052006eaULL, 0xe77d0e18ef7cb4e6ULL, 0xe79b2b895f9e651dULL, 0xf3af9c910c3e9861ULL,
    0xf42ff4190b72ee5eULL, 0xf4a04d1906ea8ea5ULL, 0xf604f1190d01642bULL, 0xf61494190d249f9fULL, 0xf6e018190b478c46ULL
};

constexpr uint64_t D9[23] = {
    0x038b2a0deba58916ULL, 0x08b05807b5566370ULL, 0x08b73807b55c4bbeULL, 0x08b73e07b55c55f0ULL, 0x08c43a07b566d980ULL, 0x08c83907b56ac0a4ULL,
    0x17b684cd2733eb8eULL, 0x19f79b1921bbcfffULL, 0x1a249b1921e2bdeaULL, 0x24b070ada2041cb0ULL, 0x3dc94a19365b10ecULL, 0x5062cd8f7a7fd349ULL,
    0x56f5c9194461d57cULL, 0x5d4728070640f60cULL, 0x6f3fb3842ffa02bbULL, 0x76aaaa535714d805ULL, 0x77203729b376a83fULL, 0x9a46ff9baa276602ULL,
    0xc2a38db44454a06fULL, 0xd6f577826e05d594ULL, 0xdc04126761bb7455ULL, 0xe26607dbf29ff924ULL, 0xf5a6c8c57a9061a3ULL
};

constexpr uint64_t D10[23] = {
    0x3021ddef38d7939cULL, 0x3e90df42f72d8096ULL, 0x4205cd01ca2cca8eULL, 0x4a6173034c7ba27dULL, 0x56f9c5194465b787ULL, 0x59950458e9e083d3ULL,
    0x5ae9eac9344ce1f7ULL, 0x5d7cd549128a7aecULL, 0x8ada49fbc8a09fb3ULL, 0x918b76d5e8ef7340ULL, 0x9caaa76c1a7404f9ULL, 0xa51a677d5b590177ULL,
    0xa66b06f655a0c2e9ULL, 0xa9ff06b0f323b67eULL, 0xbf3075ad69383fbfULL, 0xd391a4d14a5222d5ULL, 0xd55de095b179c3e8ULL, 0xd96431ef07ad2a25ULL,
    0xe4dede02383cb9ccULL, 0xe6f79719051ff286ULL, 0xe723b5190545606bULL, 0xe81b0096bc73f511ULL, 0xfbc924118177ade4ULL
};

bool isAsciiAlpha(uint32_t cp) {
    return (cp >= 'A' && cp <= 'Z') || (cp >= 'a' && cp <= 'z');
}

bool isAsciiDigit(uint32_t cp) {
    return (cp >= '0' && cp <= '9');
}

wchar_t toLowerAscii(wchar_t ch) {
    if (ch >= L'A' && ch <= L'Z') {
        return ch + (L'a' - L'A');
    }
    return ch;
}

bool hasDoubleO(const wchar_t *s, int len) {
    for (int i = 0; i + 1 < len; ++i) {
        if (s[i] == L'o' && s[i + 1] == L'o') return true;
    }
    return false;
}

bool f0(const wchar_t *init, int initLen, bool hasStrokeD) {
    if (hasStrokeD) {
        return (initLen == 1 && init[0] == L'd');
    }
    return hasSortedHash(D0, fnv1aHash(init, initLen));
}

bool f1(const wchar_t *coda, int codaLen) {
    return hasSortedHash(D1, fnv1aHash(coda, codaLen));
}

bool f2(const wchar_t *coda, int codaLen) {
    return hasSortedHash(D2, fnv1aHash(coda, codaLen));
}

bool f3(const wchar_t *coda, int codaLen) {
    return hasSortedHash(D3, fnv1aHash(coda, codaLen));
}

bool f4(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    return hasSortedHash(D4, fnv1aHash(rawLower, rawLen));
}

bool f5(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    return hasSortedHash(D5, fnv1aHash(rawLower, rawLen));
}

bool f6(const wchar_t *rawLower, int rawLen) {
    if (rawLen <= 0) return false;
    return hasSortedHash(D6, fnv1aHash(rawLower, rawLen));
}

bool f7(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(D7, fnv1aHash(w, len));
}

bool f8(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(D8, fnv1aHash(w, len));
}

bool f9(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(D9, fnv1aHash(w, len));
}

bool f10(const wchar_t *w, int len) {
    if (len <= 0) return false;
    return hasSortedHash(D10, fnv1aHash(w, len));
}

bool isLeadingSlashCommandOrPathToken(const wchar_t *rawLower, int rawLen) {
    if (rawLen < 2 || rawLen > 16) return false;
    static const wchar_t *const kSlashTokens[] = {
        L"add", L"agents", L"api", L"app", L"apps", L"ar", L"as", L"aw", L"awk", L"aws",
        L"bash", L"bin", L"boost", L"boot", L"browser", L"bug", L"build",
        L"cast", L"cash", L"clear", L"compact", L"config", L"core", L"cost",
        L"dash", L"dev", L"diff", L"dist", L"doc", L"docs", L"doctor",
        L"env", L"es", L"etc", L"ex", L"exit",
        L"fast", L"git", L"goal", L"hash", L"help", L"home", L"host",
        L"if", L"image", L"info", L"init", L"ir", L"is", L"ix",
        L"last", L"learn", L"lib", L"list", L"log", L"login", L"logout", L"logs", L"loop",
        L"mask", L"mcp", L"memory", L"mnt", L"model", L"models", L"more",
        L"new", L"of", L"opt", L"or", L"os", L"out",
        L"permissions", L"pkg", L"plan", L"port", L"post", L"pr", L"proc",
        L"quit", L"raw", L"reset", L"review", L"room", L"root", L"run",
        L"sbin", L"schedule", L"search", L"share", L"sort", L"src", L"srv", L"ssh", L"start", L"status", L"stop", L"store", L"sys",
        L"task", L"tasks", L"teamwork", L"terminal", L"test", L"tests", L"tmp", L"tool", L"tools",
        L"ur", L"us", L"user", L"users", L"usr",
        L"var", L"vim", L"voice", L"war", L"was", L"web", L"zoom"
    };
    for (const wchar_t *tok : kSlashTokens) {
        int i = 0;
        while (i < rawLen && tok[i] != L'\0' && rawLower[i] == tok[i]) {
            ++i;
        }
        if (i == rawLen && tok[i] == L'\0') {
            return true;
        }
    }
    return false;
}

struct C0 {
    wchar_t baseLower{0};
    bool isUpper{false};
    int shape{0};
};

struct S0 {
    InputMethod m_inputMethod{InputMethod::Telex};
    int32_t m_grammarProfile{1};
    bool m_smartBilingual{true};
    bool m_modernOrthography{true};
    bool m_quickTelex{false};

    wchar_t m_rawWord[kMaxWordTokens]{};
    int m_rawLen{0};

    wchar_t m_displayed[kMaxWordTokens]{};
    int m_displayedLen{0};

    wchar_t m_literalTail[kMaxWordTokens]{};
    int m_literalTailLen{0};

    C0 m_tokens[kMaxWordTokens]{};
    int m_tokenLen{0};

    int m_tone{0};
    wchar_t m_lastToneKey{0};
    wchar_t m_lastShapeKey{0};
    bool m_literalLock{false};
    bool m_shapeCancelledOnce{false};
    bool m_toneCancelledPlain{false};
    bool m_uHornFromOwnW{false};
    bool m_preVowelTone{false};

    bool m_hasUndoSnapshot{false};
    bool m_armedAfterSpace{false};
    C0 m_undoTokens[kMaxWordTokens]{};
    int m_undoTokenLen{0};
    int m_undoTone{0};
    wchar_t m_undoLastToneKey{0};
    wchar_t m_undoLastShapeKey{0};
    wchar_t m_undoRawWord[kMaxWordTokens]{};
    int m_undoRawLen{0};

    int32_t m_lastBackspaces{0};
    bool m_lastIsOverride{false};
    char m_lastTextUtf8[kMaxUtf8Bytes]{};
    bool m_inEnglishContext{false};
    bool m_lastWordWasSexLoanwordHead{false};
    bool m_precededByTechDelimiter{false};
    bool m_afterDigit{false};
    bool m_precededByLeadingSlash{false};
    uint32_t m_pendingBoundaryCp{0};
    wchar_t m_prevCollisionDisplayed[16]{};
    int m_prevCollisionDisplayedLen{0};
    wchar_t m_prevCollisionRaw[16]{};
    int m_prevCollisionRawLen{0};

    void clearWordState() {
        m_rawLen = 0;
        m_rawWord[0] = 0;
        m_displayedLen = 0;
        m_displayed[0] = 0;
        m_literalTailLen = 0;
        m_literalTail[0] = 0;
        m_tokenLen = 0;
        m_tone = 0;
        m_lastToneKey = 0;
        m_lastShapeKey = 0;
        m_literalLock = false;
        m_shapeCancelledOnce = false;
        m_toneCancelledPlain = false;
        m_uHornFromOwnW = false;
        m_preVowelTone = false;
        m_hasUndoSnapshot = false;
        m_armedAfterSpace = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
    }

    bool isComposing() const {
        return m_displayedLen > 0 || m_armedAfterSpace;
    }

    void m5();
    void setInputMethod(InputMethod method);
    static bool m13(uint32_t cp);
    static bool m12(wchar_t lowerCh);
    static wchar_t m11(const C0 &tok, int tone);
    static void m10(const wchar_t *wstr, int wlen, char *outUtf8, int maxOut);
    void m2(int &outStart, int &outEnd, bool &outHasCoda) const;
    int m3(int vowelStart, int vowelEnd, bool hasCoda) const;
    bool m4() const;
    bool m0() const;
    bool m1() const;
    int m6(wchar_t *outBuf, int maxLen) const;
    bool m7(wchar_t ch, wchar_t lowerCh, bool isUpper);
    bool m8(wchar_t ch);
    int32_t m9(const wchar_t *priorDisplayed, int priorLen, const wchar_t *newDisplayed, int newLen);
    int32_t feedChar(uint32_t codepoint);
    int32_t feedBackspace();
    int32_t commitWord();
};

void S0::m5() {
    m_hasUndoSnapshot = true;
    m_undoTokenLen = m_tokenLen;
    for (int i = 0; i < m_tokenLen; ++i) {
        m_undoTokens[i] = m_tokens[i];
    }
    m_undoTone = m_tone;
    m_undoRawLen = (m_rawLen > 0) ? (m_rawLen - 1) : 0;
    for (int i = 0; i < m_undoRawLen; ++i) {
        m_undoRawWord[i] = m_rawWord[i];
    }
    m_undoRawWord[m_undoRawLen] = 0;
}

void S0::setInputMethod(InputMethod method) {
    if (m_inputMethod != method) {
        m_inputMethod = method;
        clearWordState();
    }
}

bool S0::m13(uint32_t cp) {
    if (cp == ' ' || cp == '\t' || cp == '\r' || cp == '\n') return true;
    switch (cp) {
    case ',': case ';': case ':': case '!': case '?':
    case '"': case '\'': case '(': case ')': case '[':
    case ']': case '{': case '}': case '<': case '>':
    case '-': case '/': case '\\': case '.': case '_':
        return true;
    default:
        return false;
    }
}

bool S0::m12(wchar_t lowerCh) {
    return lowerCh == L'a' || lowerCh == L'e' || lowerCh == L'i' ||
           lowerCh == L'o' || lowerCh == L'u' || lowerCh == L'y';
}

wchar_t S0::m11(const C0 &tok, int tone) {
    if (tok.baseLower == L'd') {
        if (tok.shape == 4) {
            return tok.isUpper ? static_cast<wchar_t>(0x0110) : static_cast<wchar_t>(0x0111);
        }
        return tok.isUpper ? L'D' : L'd';
    }

    int row = -1;
    switch (tok.baseLower) {
    case L'a':
        if (tok.shape == 3) row = 1;      // ă
        else if (tok.shape == 1) row = 2; // â
        else row = 0;                     // a
        break;
    case L'e':
        row = (tok.shape == 1) ? 4 : 3;   // ê : e
        break;
    case L'i':
        row = 5;
        break;
    case L'o':
        if (tok.shape == 1) row = 7;      // ô
        else if (tok.shape == 2) row = 8; // ơ
        else row = 6;                     // o
        break;
    case L'u':
        row = (tok.shape == 2) ? 10 : 9;  // ư : u
        break;
    case L'y':
        row = 11;
        break;
    default:
        break;
    }

    if (row >= 0 && tone >= 0 && tone <= 5) {
        return tok.isUpper ? V1[row][tone] : V0[row][tone];
    }

    return tok.isUpper ? static_cast<wchar_t>(tok.baseLower - (L'a' - L'A')) : tok.baseLower;
}

void S0::m10(const wchar_t *wstr, int wlen, char *outUtf8, int maxOut) {
    int pos = 0;
    for (int i = 0; i < wlen && pos + 4 < maxOut; ++i) {
        uint32_t cp = static_cast<uint32_t>(wstr[i]);
        if constexpr (sizeof(wchar_t) == 2) {
            if (cp >= 0xD800 && cp <= 0xDBFF && (i + 1) < wlen) {
                uint32_t low = static_cast<uint32_t>(wstr[i + 1]);
                if (low >= 0xDC00 && low <= 0xDFFF) {
                    cp = 0x10000 + (((cp - 0xD800) << 10) | (low - 0xDC00));
                    ++i;
                }
            }
        }
        if (cp <= 0x7F) {
            outUtf8[pos++] = static_cast<char>(cp);
        } else if (cp <= 0x7FF) {
            outUtf8[pos++] = static_cast<char>(0xC0 | ((cp >> 6) & 0x1F));
            outUtf8[pos++] = static_cast<char>(0x80 | (cp & 0x3F));
        } else if (cp <= 0xFFFF) {
            outUtf8[pos++] = static_cast<char>(0xE0 | ((cp >> 12) & 0x0F));
            outUtf8[pos++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            outUtf8[pos++] = static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            outUtf8[pos++] = static_cast<char>(0xF0 | ((cp >> 18) & 0x07));
            outUtf8[pos++] = static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
            outUtf8[pos++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            outUtf8[pos++] = static_cast<char>(0x80 | (cp & 0x3F));
        }
    }
    outUtf8[pos] = '\0';
}

void S0::m2(int &outStart, int &outEnd, bool &outHasCoda) const {
    outStart = -1;
    outEnd = -1;
    outHasCoda = false;

    const int n = m_tokenLen;
    int i = 0;
    while (i < n && !m12(m_tokens[i].baseLower)) {
        ++i;
    }
    if (i >= n) return;

    // Handle 'qu' + vowel where 'u' is part of the initial consonant
    if (i == 1 && m_tokens[0].baseLower == L'q' && m_tokens[1].baseLower == L'u' && m_tokens[1].shape == 0) {
        if (i + 1 < n && m12(m_tokens[i + 1].baseLower)) {
            ++i;
        }
    }
    // Handle 'gi' + vowel where 'i' is part of the initial consonant
    else if (i == 1 && m_tokens[0].baseLower == L'g' && m_tokens[1].baseLower == L'i' && m_tokens[1].shape == 0) {
        if (i + 1 < n && m12(m_tokens[i + 1].baseLower)) {
            ++i;
        }
    }

    outStart = i;
    while (i < n && m12(m_tokens[i].baseLower)) {
        outEnd = i;
        ++i;
    }
    outHasCoda = (outEnd + 1 < n);
}

int S0::m3(int vowelStart, int vowelEnd, bool hasCoda) const {
    if (vowelStart < 0 || vowelEnd < vowelStart) return -1;
    int len = vowelEnd - vowelStart + 1;
    if (len == 1) return vowelStart;

    // If 'ươ' is present, tone goes on 'ơ'
    for (int i = vowelStart; i < vowelEnd; ++i) {
        if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
            m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
            return i + 1;
        }
    }

    // Otherwise if any vowel has a diacritic shape (ă, â, ê, ô, ơ, ư), tone goes on it
    for (int i = vowelStart; i <= vowelEnd; ++i) {
        if (m_tokens[i].shape != 0) {
            return i;
        }
    }

    if (len == 2) {
        if (hasCoda) {
            return vowelStart + 1;
        }
        wchar_t v1 = m_tokens[vowelStart].baseLower;
        wchar_t v2 = m_tokens[vowelStart + 1].baseLower;
        if (m_modernOrthography && ((v1 == L'o' && (v2 == L'a' || v2 == L'e')) || (v1 == L'u' && v2 == L'y'))) {
            return vowelStart + 1;
        }
        return vowelStart;
    }

    // 3 vowels (oai, oay, uây, uôi, ươi, iêu, yêu, uya)
    return vowelStart + 1;
}

bool S0::m4() const {
    if (m_tone != 0) return true;
    for (int i = 0; i < m_tokenLen; ++i) {
        if (m_tokens[i].shape != 0) return true;
    }
    if (m_tokenLen + m_literalTailLen < m_rawLen) return true;
    return false;
}

bool S0::m0() const {
    if (m_tokenLen == 0) return true;

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    m2(vStart, vEnd, hasCoda);

    if (vStart == -1) {
        if (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4) {
            return true;
        }
        bool hasStrokeDToken = false;
        for (int i = 0; i < m_tokenLen; ++i) {
            if (m_tokens[i].baseLower == L'd' && m_tokens[i].shape == 4) {
                hasStrokeDToken = true;
                break;
            }
        }
        if (hasStrokeDToken && m_tokenLen >= 2 && m_tone == 0 && m_literalTailLen == 0) {
            if (m_tokenLen == 2 &&
                m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4 && !m_tokens[0].isUpper &&
                m_tokens[1].baseLower == L'r' && !m_tokens[1].isUpper) {
                return false;
            }
            return true;
        }
        return false;
    }

    wchar_t initStr[16]{};
    int initLen = 0;
    for (int i = 0; i < vStart && initLen < 15; ++i) {
        initStr[initLen++] = m_tokens[i].baseLower;
    }
    bool hasStrokeD = (vStart == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
    if (!f0(initStr, initLen, hasStrokeD)) {
        return false;
    }

    if (m_literalTailLen > 0) return false;

    int vLen = vEnd - vStart + 1;
    if (vLen > 3) return false;

    wchar_t codaStr[16]{};
    int codaLen = 0;
    for (int i = vEnd + 1; i < m_tokenLen; ++i) {
        if (m12(m_tokens[i].baseLower)) {
            return false;
        }
        if (codaLen < 15) {
            codaStr[codaLen++] = m_tokens[i].baseLower;
        }
    }

    if (!f1(codaStr, codaLen)) {
        return false;
    }

    // Initial 'p' (without 'h') never precedes 'ư' in Vietnamese (e.g. 'pwd' -> 'pưd')
    if (initLen == 1 && initStr[0] == L'p' && m_tokens[vStart].baseLower == L'u' && m_tokens[vStart].shape == 2) {
        return false;
    }

    if (vLen == 2) {
        wchar_t v1 = m_tokens[vStart].baseLower;
        int s1 = m_tokens[vStart].shape;
        wchar_t v2 = m_tokens[vStart + 1].baseLower;
        int s2 = m_tokens[vStart + 1].shape;
        bool validPair = false;
        if (v1 == L'a') {
            if ((v2 == L'i' || v2 == L'o') && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if ((v2 == L'u' || v2 == L'y') && (s1 == 0 || s1 == 1) && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'e') {
            if (v2 == L'o' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'u' && s1 == 1 && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'i') {
            if (v2 == L'a' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
            else if (v2 == L'u' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'o') {
            if (v2 == L'a' && s1 == 0 && (s2 == 0 || s2 == 3)) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 0) validPair = true;
            else if (v2 == L'i' && (s1 == 0 || s1 == 1 || s1 == 2) && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'o' && s1 == 0 && s2 == 0 && f3(codaStr, codaLen)) validPair = true;
        } else if (v1 == L'u') {
            if (v2 == L'a' && ((s1 == 0 && (s2 == 0 || s2 == 1)) || (s1 == 2 && s2 == 0 && codaLen == 0))) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
            else if (v2 == L'i' && (s1 == 0 || s1 == 2) && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'o' && ((s1 == 0 && s2 == 1) || (s1 == 2 && s2 == 2) || (codaLen == 0 && s1 == 2 && s2 == 0))) validPair = true;
            else if (v2 == L'y' && s1 == 0 && s2 == 0) validPair = true;
            else if (v2 == L'u' && s1 == 2 && s2 == 0 && codaLen == 0) validPair = true;
        } else if (v1 == L'y') {
            if (v2 == L'a' && s1 == 0 && s2 == 0 && codaLen == 0) validPair = true;
            else if (v2 == L'e' && s1 == 0 && s2 == 1) validPair = true;
        }
        if (!validPair) return false;
    } else if (vLen == 3) {
        wchar_t v1 = m_tokens[vStart].baseLower;
        int s1 = m_tokens[vStart].shape;
        wchar_t v2 = m_tokens[vStart + 1].baseLower;
        int s2 = m_tokens[vStart + 1].shape;
        wchar_t v3 = m_tokens[vStart + 2].baseLower;
        int s3 = m_tokens[vStart + 2].shape;
        bool validTrip = false;
        if ((v1 == L'i' || v1 == L'y') && v2 == L'e' && v3 == L'u' && s1 == 0 && s2 == 1 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'o' && v2 == L'a' && (v3 == L'i' || v3 == L'y') && s1 == 0 && s2 == 0 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'a' && v3 == L'y' && s1 == 0 && s2 == 1 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'o' && (v3 == L'i' || v3 == L'u') && ((s1 == 0 && s2 == 1 && v3 == L'i') || (s1 == 2 && s2 == 2)) && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'a' && s1 == 0 && s2 == 0 && s3 == 0 && codaLen == 0) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'e' && s1 == 0 && s2 == 0 && s3 == 1) validTrip = true;
        else if (v1 == L'u' && v2 == L'y' && v3 == L'u' && s1 == 0 && s2 == 0 && s3 == 0 && codaLen == 0) validTrip = true;
        if (!validTrip) return false;
    }

    // "ươ" cannot pair with palatal codas "ch" or "nh" in Vietnamese phonotactics
    if (codaLen == 2 && codaStr[1] == L'h' && (codaStr[0] == L'c' || codaStr[0] == L'n')) {
        for (int i = vStart; i < vEnd; ++i) {
            if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o') {
                return false;
            }
        }
    }

    if (f2(codaStr, codaLen) && m_tone != 0 && m_tone != 1 && m_tone != 5) {
        return false;
    }

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) {
        rawLower[i] = toLowerAscii(m_rawWord[i]);
    }

    if (hasDoubleO(rawLower, m_rawLen) && codaLen > 0 && !f3(codaStr, codaLen)) {
        return false;
    }

    if (m_rawLen >= 2 && rawLower[0] == L'w') {
        wchar_t second = rawLower[1];
        if (second == L'h' || second == L'o' || second == L'e' || (second == L'r' && m_rawLen >= 3) || second == L'l' ||
            (second == L'i' && m_rawLen >= 3 && rawLower[2] != L'u')) {
            return false;
        }
    }

    if (m_preVowelTone) {
        bool hasVowelShape = false;
        for (int i = vStart; i <= vEnd; ++i) {
            if (m_tokens[i].shape != 0) {
                hasVowelShape = true;
                break;
            }
        }
        if (!hasVowelShape) {
            return false;
        }
    }

    return true;
}

bool S0::m1() const {
    if (!m_smartBilingual || !m4()) return false;
    if (!m0()) return true;

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) {
        rawLower[i] = toLowerAscii(m_rawWord[i]);
    }

    if (f4(rawLower, m_rawLen)) {
        return true;
    }
    if (m_precededByLeadingSlash && isLeadingSlashCommandOrPathToken(rawLower, m_rawLen)) {
        return true;
    }
    if (f5(rawLower, m_rawLen)) {
        if (m_precededByTechDelimiter) return true;
        if (m_pendingBoundaryCp == '_' || m_pendingBoundaryCp == '/' || m_pendingBoundaryCp == '.') return true;
        if (m_rawLen == 3 && rawLower[0] == L's' && rawLower[1] == L'e' && rawLower[2] == L'x') {
            if (m_lastWordWasSexLoanwordHead) return true;
        }
        if (m_inEnglishContext) return true;
    }
    return false;
}

int S0::m6(wchar_t *outBuf, int maxLen) const {
    if (m_smartBilingual && m4() && m1()) {
        int n = (m_rawLen < maxLen - 1) ? m_rawLen : (maxLen - 1);
        for (int i = 0; i < n; ++i) outBuf[i] = m_rawWord[i];
        outBuf[n] = 0;
        return n;
    }

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    m2(vStart, vEnd, hasCoda);
    int toneIdx = (m_tone != 0) ? m3(vStart, vEnd, hasCoda) : -1;

    int outLen = 0;
    for (int i = 0; i < m_tokenLen && outLen < maxLen - 1; ++i) {
        int t = (i == toneIdx) ? m_tone : 0;
        outBuf[outLen++] = m11(m_tokens[i], t);
    }
    for (int i = 0; i < m_literalTailLen && outLen < maxLen - 1; ++i) {
        outBuf[outLen++] = m_literalTail[i];
    }
    outBuf[outLen] = 0;
    return outLen;
}

bool S0::m7(wchar_t ch, wchar_t lowerCh, bool isUpper) {
    if (m_literalLock) return false;
    if (m_literalTailLen > 0) {
        if (m_toneCancelledPlain && lowerCh != m_lastToneKey) {
            m_toneCancelledPlain = false;
        }
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        return true;
    }

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    m2(vStart, vEnd, hasCoda);

    // 1. Tone-Only 'z' (removes ONLY tone s/f/r/x/j, preserves ă/â/ê/ô/ơ/ư/đ)
    if (lowerCh == L'z') {
        if (m_tone != 0) {
            m5();
            m_tone = 0;
            m_lastToneKey = L'z';
            m_lastShapeKey = 0;
            return true;
        }
        if (m4()) {
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }
        return false;
    }

    // 2. 'd' -> 'đ'
    if (lowerCh == L'd') {
        if (vStart == -1 && m_tokenLen >= 1 && m_tokens[m_tokenLen - 1].baseLower == L'd') {
            if (m_tokens[m_tokenLen - 1].shape == 0) {
                m_tokens[m_tokenLen - 1].shape = 4;
                m_lastShapeKey = L'd';
                m_lastToneKey = 0;
                return true;
            } else if (m_tokens[m_tokenLen - 1].shape == 4 && m_lastShapeKey == L'd') {
                m_tokens[m_tokenLen - 1].shape = 0;
                m_literalLock = true;
                return false;
            }
        }
        if (m_tokenLen > 0 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 0 && vStart == 1 && !hasCoda && m_tone == 0) {
            bool hasVnFeature = false;
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].shape != 0) hasVnFeature = true;
            }
            if (!hasVnFeature && (vEnd - vStart + 1) >= 2 &&
                m_tokens[vStart].baseLower == L'u' && m_tokens[vStart + 1].baseLower == L'o') {
                hasVnFeature = true;
            }
            if (hasVnFeature) {
                m_tokens[0].shape = 4;
                m_lastShapeKey = L'd';
                return true;
            }
        }
        return false;
    }

    // 3. Circumflex 'a' -> 'â', 'e' -> 'ê', 'o' -> 'ô' AND Vowel-Shape Cancellation (088fc45)
    if (lowerCh == L'a' || lowerCh == L'e' || lowerCh == L'o') {
        // If we already cancelled a vowel shape once on the immediately preceding key, the 2nd extra press appends literally!
        if (m_shapeCancelledOnce && m_lastShapeKey == lowerCh) {
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        // Mutual exclusion reshape: 'trương' + 'o' -> 'truông' (ươ -> uô, only when not already finalized with coda + tone)
        if (lowerCh == L'o' && vStart != -1 && !(hasCoda && m_tone != 0)) {
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                    m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
                    m5();
                    m_tokens[i].shape = 0;
                    m_tokens[i + 1].shape = 1;
                    m_lastShapeKey = L'o';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    m_uHornFromOwnW = false;
                    return true;
                }
            }
            // Single 'ơ' + 'o' -> 'ô' (e.g. 'cơ' + 'o' -> 'cô', 'hơn' + 'o' -> 'hôn')
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 2) {
                    m5();
                    m_tokens[i].shape = 1;
                    m_lastShapeKey = L'o';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
        }

        // Mutual exclusion reshape: 'căn' + 'a' -> 'cân' (ă -> â)
        if (lowerCh == L'a' && vStart != -1 && !(hasCoda && m_tone != 0)) {
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3) {
                    m5();
                    m_tokens[i].shape = 1;
                    m_lastShapeKey = L'a';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
        }

        // Check if vowel in vStart..vEnd already has circumflex (shape == 1) for lowerCh:
        if (vStart != -1 && !(hasCoda && m_tone != 0)) {
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].baseLower == lowerCh && m_tokens[i].shape == 1) {
                    if (!hasCoda && m_tone == 0 && vStart == vEnd && m_lastShapeKey == lowerCh) {
                        m_tokens[i].shape = 0;
                        m_literalLock = true;
                        return false;
                    }
                    m5();
                    m_tokens[i].shape = 0;
                    m_lastShapeKey = lowerCh;
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = true;
                    return true;
                }
            }
        }

        // Adjacent vowel doubling (Including late vowel modification after tone: 'đẻ' + 'e' -> 'để', 'đó' + 'o' -> 'đố', 'cá' + 'a' -> 'cấ')
        if (m_tokenLen > 0 && m_tokens[m_tokenLen - 1].baseLower == lowerCh && m_tokens[m_tokenLen - 1].shape == 0) {
            m_tokens[m_tokenLen - 1].shape = 1;
            m_lastShapeKey = lowerCh;
            m_lastToneKey = 0;
            m_shapeCancelledOnce = false;
            return true;
        }

        // Non-adjacent SEN Flex circumflex (e.g. 'ama' -> 'âm', 'eme' -> 'êm', 'cana' -> 'cân', 'toiso' -> 'tối')
        if (vStart != -1 && (hasCoda || vEnd > vStart)) {
            wchar_t codaStr[16]{};
            int codaLen = 0;
            for (int i = vEnd + 1; i < m_tokenLen && codaLen < 15; ++i) {
                codaStr[codaLen++] = m_tokens[i].baseLower;
            }
            if (f1(codaStr, codaLen)) {
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].baseLower == lowerCh && m_tokens[i].shape == 0) {
                        m_tokens[i].shape = 1;
                        m_lastShapeKey = lowerCh;
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                }
            }
        }

        // If 'o' follows standalone 'w' + ('f') + 'u' ('trwfuong' / 'trwuong' -> 'trường' / 'trương')
        if (lowerCh == L'o' && vStart != -1 && (vEnd - vStart == 1) &&
            m_tokens[vStart].baseLower == L'u' && m_tokens[vStart].shape == 2 &&
            m_tokens[vEnd].baseLower == L'u' && m_tokens[vEnd].shape == 0 && m_uHornFromOwnW) {
            m_tokens[vEnd] = C0{ L'o', isUpper, 2 };
            m_lastShapeKey = 0;
            m_lastToneKey = 0;
            m_shapeCancelledOnce = false;
            return true;
        }
        return false;
    }

    // 4. Horn / Breve 'w' AND Vowel-Shape Cancellation (những + w -> nhũng, được + w -> đuọc, chứng + w -> chúng, trường + w -> truòng, cử + w -> củ, cửa + w -> của)
    if (lowerCh == L'w') {
        if (m_shapeCancelledOnce && m_lastShapeKey == L'w') {
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        if (vStart != -1) {
            // Absorb 2nd 'w' in 'dduwowng' ('ư' got horn from 1st 'w', then 'o' was typed and upgraded to 'ươ', then user immediately typed 'w' for 'ơ' before coda/tone)
            if (!hasCoda && m_tone == 0) {
                for (int i = vStart; i < vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                        m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2 &&
                        m_uHornFromOwnW && m_lastShapeKey != L'w') {
                        m_uHornFromOwnW = false;
                        m_lastShapeKey = L'w';
                        return true;
                    }
                }
            }

            bool alreadyHasHornOrBreve = false;
            for (int i = vStart; i <= vEnd; ++i) {
                if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3) {
                    alreadyHasHornOrBreve = true;
                    break;
                }
            }
            // Compound 'uo' / 'ưo' / 'uơ' -> 'ươ'
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o') {
                    if (m_tokens[i].shape != 2 || m_tokens[i + 1].shape != 2) {
                        m_tokens[i].shape = 2;
                        m_tokens[i + 1].shape = 2;
                        m_lastShapeKey = L'w';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        m_uHornFromOwnW = false;
                        return true;
                    }
                }
            }

            // Mutual exclusion reshape: 'cân' + 'w' -> 'căn', 'côn' + 'w' -> 'cơn'
            if (!(hasCoda && m_tone != 0)) {
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 1) {
                        m5();
                        m_tokens[i].shape = 3;
                        m_lastShapeKey = L'w';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                    if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 1) {
                        m5();
                        m_tokens[i].shape = 2;
                        m_lastShapeKey = L'w';
                        m_lastToneKey = 0;
                        m_shapeCancelledOnce = false;
                        return true;
                    }
                }
            }

            if (alreadyHasHornOrBreve) {
                if (hasCoda && m_tone != 0) {
                    return false;
                }
                // Immediate double 'ww' at word start ('ww' -> 'w')
                if (m_rawLen == 2 && (m_rawWord[0] == L'w' || m_rawWord[0] == L'W')) {
                    m_tokenLen = 0;
                    m_literalLock = true;
                    return false;
                }
                // Classic open untoned single vowel ('oww' -> 'ow', 'uww' -> 'uw', 'aww' -> 'aw')
                if (!hasCoda && m_tone == 0 && vStart == vEnd && m_lastShapeKey == L'w') {
                    for (int i = vStart; i <= vEnd; ++i) {
                        if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3) {
                            m_tokens[i].shape = 0;
                        }
                    }
                    m_literalLock = true;
                    return false;
                }
                // Strip horn/breve while preserving tone and coda when not finalized with coda + tone
                m5();
                for (int i = vStart; i <= vEnd; ++i) {
                    if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3) {
                        m_tokens[i].shape = 0;
                    }
                }
                m_lastShapeKey = L'w';
                m_lastToneKey = 0;
                m_shapeCancelledOnce = true;
                m_uHornFromOwnW = false;
                return true;
            }

            // 'oa' + 'w' -> 'oă'
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'o' && m_tokens[i + 1].baseLower == L'a' && m_tokens[i + 1].shape == 0) {
                    m_tokens[i + 1].shape = 3;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }

            // 'uu' + 'w' -> 'ưu' (e.g. 'cuuws' -> 'cứu', 'huuw' -> 'hưu', 'luuw' -> 'lưu')
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'u' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 2;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    m_uHornFromOwnW = true;
                    return true;
                }
            }

            // Single 'a' -> 'ă', 'o' -> 'ơ', 'u' -> 'ư'
            for (int i = vEnd; i >= vStart; --i) {
                if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 3;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
                if (m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 2;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    return true;
                }
                if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 0) {
                    m_tokens[i].shape = 2;
                    m_lastShapeKey = L'w';
                    m_lastToneKey = 0;
                    m_shapeCancelledOnce = false;
                    m_uHornFromOwnW = true;
                    return true;
                }
            }
            return false;
        } else {
            // No vowel yet: standalone 'w' -> 'ư' if at start or after valid Vietnamese initial
            wchar_t initStr[16]{};
            int initLen = 0;
            for (int i = 0; i < m_tokenLen && initLen < 15; ++i) {
                initStr[initLen++] = m_tokens[i].baseLower;
            }
            bool hasStrokeD = (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
            if (!hasStrokeD && f0(initStr, initLen, false) && m_tokenLen < kMaxWordTokens) {
                m_tokens[m_tokenLen++] = C0{ L'u', isUpper, 2 };
                m_lastShapeKey = L'w';
                m_lastToneKey = 0;
                m_shapeCancelledOnce = false;
                m_uHornFromOwnW = true;
                return true;
            }
            return false;
        }
    }

    // 5. Tone keys: s (1), f (2), r (3), x (4), j (5)
    int targetTone = 0;
    switch (lowerCh) {
    case L's': targetTone = 1; break;
    case L'f': targetTone = 2; break;
    case L'r': targetTone = 3; break;
    case L'x': targetTone = 4; break;
    case L'j': targetTone = 5; break;
    default: break;
    }

    if (targetTone != 0 && vStart != -1) {
        wchar_t codaStr[16]{};
        int codaLen = 0;
        for (int i = vEnd + 1; i < m_tokenLen; ++i) {
            if (m12(m_tokens[i].baseLower)) return false;
            if (codaLen < 15) codaStr[codaLen++] = m_tokens[i].baseLower;
        }
        if (!f1(codaStr, codaLen)) {
            return false;
        }
        if (f2(codaStr, codaLen) && targetTone != 1 && targetTone != 5) {
            return false;
        }

        if (m_tone == targetTone && m_lastToneKey != lowerCh) {
            return false;
        }
        if (m_tone == targetTone && m_lastToneKey == lowerCh) {
            m5();
            m_tone = 0;
            bool hasModifiedShape = m_shapeCancelledOnce;
            for (int i = 0; i < m_tokenLen; ++i) {
                if (m_tokens[i].shape != 0) {
                    hasModifiedShape = true;
                    break;
                }
            }
            m_toneCancelledPlain = !hasModifiedShape;
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }

        m_tone = targetTone;
        m_lastToneKey = lowerCh;
        m_lastShapeKey = 0;
        m_shapeCancelledOnce = false;
        return true;
    }

    // SEN Flex pre-vowel tone (e.g. "tseet" -> "tết"): tone key typed right after initial consonant before vowel
    if (m_grammarProfile == 1 && targetTone != 0 && lowerCh != L'r' && vStart == -1 && m_tokenLen > 0 && m_tone == 0) {
        wchar_t initStr[16]{};
        int initLen = 0;
        for (int i = 0; i < m_tokenLen && initLen < 15; ++i) {
            initStr[initLen++] = m_tokens[i].baseLower;
        }
        bool hasStrokeD = (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4);
        if (!hasStrokeD && f0(initStr, initLen, false) && !(initLen == 1 && initStr[0] == L'p' && lowerCh == L's')) {
            m_tone = targetTone;
            m_lastToneKey = lowerCh;
            m_preVowelTone = true;
            return true;
        }
    }

    // Quick Telex onset shortcuts (cc=ch, gg=gi, qq=qu)
    if (m_quickTelex && vStart == -1 && m_tokenLen == 1 && m_tokens[0].shape == 0 && m_tokens[0].baseLower == lowerCh) {
        if (lowerCh == L'c' && m_tokenLen < kMaxWordTokens) {
            m_tokens[m_tokenLen++] = C0{ L'h', false, 0 };
            return true;
        }
        if (lowerCh == L'g' && m_tokenLen < kMaxWordTokens) {
            m_tokens[m_tokenLen++] = C0{ L'i', false, 0 };
            return true;
        }
        if (lowerCh == L'q' && m_tokenLen < kMaxWordTokens) {
            m_tokens[m_tokenLen++] = C0{ L'u', false, 0 };
            return true;
        }
    }

    return false;
}

bool S0::m8(wchar_t ch) {
    if (m_literalLock) return false;
    if (m_literalTailLen > 0) {
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        return true;
    }
    if (ch < L'0' || ch > L'9') return false;

    int vStart = -1, vEnd = -1;
    bool hasCoda = false;
    m2(vStart, vEnd, hasCoda);

    if (ch == L'0') {
        if (m_tone != 0) {
            m5();
            m_tone = 0;
            m_lastToneKey = 0;
            return true;
        }
        return false;
    }

    if (ch == L'9') {
        if (m_tokenLen > 0 && m_tokens[0].baseLower == L'd') {
            if (m_tokens[0].shape == 0) {
                m_tokens[0].shape = 4;
                m_lastShapeKey = L'9';
                return true;
            } else if (m_tokens[0].shape == 4 && m_lastShapeKey == L'9') {
                m_tokens[0].shape = 0;
                m_literalLock = true;
                return false;
            }
        }
        return false;
    }

    if (vStart == -1) return false;

    if (m_shapeCancelledOnce && m_lastShapeKey == ch) {
        if (m_literalTailLen < kMaxWordTokens - 1) {
            m_literalTail[m_literalTailLen++] = ch;
            m_literalTail[m_literalTailLen] = 0;
        }
        return true;
    }

    if (ch == L'6') {
        // Mutual exclusion reshape: 'trương' + '6' -> 'truông', 'cơn' + '6' -> 'côn', 'căn' + '6' -> 'cân'
        if (!(hasCoda && m_tone != 0)) {
            for (int i = vStart; i < vEnd; ++i) {
                if (m_tokens[i].baseLower == L'u' && m_tokens[i].shape == 2 &&
                    m_tokens[i + 1].baseLower == L'o' && m_tokens[i + 1].shape == 2) {
                    m5();
                    m_tokens[i].shape = 0;
                    m_tokens[i + 1].shape = 1;
                    m_lastShapeKey = L'6';
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
            for (int i = vStart; i <= vEnd; ++i) {
                if ((m_tokens[i].baseLower == L'o' && m_tokens[i].shape == 2) ||
                    (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3)) {
                    m5();
                    m_tokens[i].shape = 1;
                    m_lastShapeKey = L'6';
                    m_shapeCancelledOnce = false;
                    return true;
                }
            }
        }
        // Vowel-shape cancellation: 'không' + '6' -> 'khong6', 'quyết' + '6' -> 'quyét6'
        for (int i = vStart; i <= vEnd; ++i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'a' || b == L'e' || b == L'o') && m_tokens[i].shape == 1) {
                m5();
                m_tokens[i].shape = 0;
                m_lastShapeKey = L'6';
                m_shapeCancelledOnce = true;
                if (m_literalTailLen < kMaxWordTokens - 1) {
                    m_literalTail[m_literalTailLen++] = ch;
                    m_literalTail[m_literalTailLen] = 0;
                }
                return true;
            }
        }
        for (int i = vEnd; i >= vStart; --i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'a' || b == L'e' || b == L'o') && m_tokens[i].shape != 1) {
                m_tokens[i].shape = 1;
                m_lastShapeKey = L'6';
                m_shapeCancelledOnce = false;
                return true;
            }
        }
        return false;
    }

    if (ch == L'7') {
        for (int i = vStart; i < vEnd; ++i) {
            if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o') {
                if (m_tokens[i].shape != 2 || m_tokens[i + 1].shape != 2) {
                    m_tokens[i].shape = 2;
                    m_tokens[i + 1].shape = 2;
                    m_lastShapeKey = L'7';
                    m_shapeCancelledOnce = false;
                    return true;
                } else {
                    // Cancel 'ươ' + '7' -> 'uo7' (e.g. 'trường' + '7' -> 'truòng7')
                    m5();
                    m_tokens[i].shape = 0;
                    m_tokens[i + 1].shape = 0;
                    m_lastShapeKey = L'7';
                    m_shapeCancelledOnce = true;
                    if (m_literalTailLen < kMaxWordTokens - 1) {
                        m_literalTail[m_literalTailLen++] = ch;
                        m_literalTail[m_literalTailLen] = 0;
                    }
                    return true;
                }
            }
        }
        for (int i = vStart; i <= vEnd; ++i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'o' || b == L'u') && m_tokens[i].shape == 2) {
                m5();
                m_tokens[i].shape = 0;
                m_lastShapeKey = L'7';
                m_shapeCancelledOnce = true;
                if (m_literalTailLen < kMaxWordTokens - 1) {
                    m_literalTail[m_literalTailLen++] = ch;
                    m_literalTail[m_literalTailLen] = 0;
                }
                return true;
            }
        }
        for (int i = vEnd; i >= vStart; --i) {
            wchar_t b = m_tokens[i].baseLower;
            if ((b == L'o' || b == L'u') && m_tokens[i].shape != 2) {
                m_tokens[i].shape = 2;
                m_lastShapeKey = L'7';
                m_shapeCancelledOnce = false;
                return true;
            }
        }
        return false;
    }

    if (ch == L'8') {
        for (int i = vStart; i <= vEnd; ++i) {
            if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape == 3) {
                m5();
                m_tokens[i].shape = 0;
                m_lastShapeKey = L'8';
                m_shapeCancelledOnce = true;
                if (m_literalTailLen < kMaxWordTokens - 1) {
                    m_literalTail[m_literalTailLen++] = ch;
                    m_literalTail[m_literalTailLen] = 0;
                }
                return true;
            }
        }
        for (int i = vEnd; i >= vStart; --i) {
            if (m_tokens[i].baseLower == L'a' && m_tokens[i].shape != 3) {
                m_tokens[i].shape = 3;
                m_lastShapeKey = L'8';
                m_shapeCancelledOnce = false;
                return true;
            }
        }
        return false;
    }

    if (ch >= L'1' && ch <= L'5') {
        int targetTone = ch - L'0';
        wchar_t codaStr[16]{};
        int codaLen = 0;
        for (int i = vEnd + 1; i < m_tokenLen; ++i) {
            if (m12(m_tokens[i].baseLower)) return false;
            if (codaLen < 15) codaStr[codaLen++] = m_tokens[i].baseLower;
        }
        if (!f1(codaStr, codaLen)) {
            return false;
        }
        if (f2(codaStr, codaLen) && targetTone != 1 && targetTone != 5) {
            return false;
        }
        if (m_tone == targetTone && m_lastToneKey == ch) {
            m5();
            m_tone = 0;
            m_lastToneKey = 0;
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
            return true;
        }
        m_tone = targetTone;
        m_lastToneKey = ch;
        return true;
    }

    return false;
}

int32_t S0::m9(const wchar_t *priorDisplayed, int priorLen, const wchar_t *newDisplayed, int newLen) {
    int commonPrefix = 0;
    const int minLen = (priorLen < newLen) ? priorLen : newLen;
    while (commonPrefix < minLen && priorDisplayed[commonPrefix] == newDisplayed[commonPrefix]) {
        ++commonPrefix;
    }

    m_lastBackspaces = static_cast<int32_t>(priorLen - commonPrefix);
    m10(newDisplayed + commonPrefix, newLen - commonPrefix, m_lastTextUtf8, kMaxUtf8Bytes);
    return static_cast<int32_t>(Action::Replace);
}

int32_t S0::feedChar(uint32_t codepoint) {
    if (m_armedAfterSpace) {
        m_armedAfterSpace = false;
        m_hasUndoSnapshot = false;
    }

    if (m13(codepoint)) {
        m_afterDigit = false;
        const bool wasInLeadingSlash = m_precededByLeadingSlash;
        m_pendingBoundaryCp = codepoint;
        if (m_displayedLen > 0) {
            int32_t act = commitWord();
            m_pendingBoundaryCp = 0;
            m_precededByLeadingSlash = (codepoint == '/' && wasInLeadingSlash);
            if (codepoint == '/' || codepoint == '\\' || codepoint == '_') {
                m_precededByTechDelimiter = true;
            } else if (codepoint == ' ' || codepoint == '\t' || codepoint == '\n' || codepoint == '\r') {
                m_precededByTechDelimiter = false;
            }
            return act;
        }
        m_pendingBoundaryCp = 0;
        m_prevCollisionDisplayedLen = 0;
        m_prevCollisionRawLen = 0;
        m_precededByLeadingSlash = (codepoint == '/');
        if (codepoint == '/' || codepoint == '\\' || codepoint == '_') {
            m_precededByTechDelimiter = true;
        } else if (codepoint == ' ' || codepoint == '\t' || codepoint == '\n' || codepoint == '\r') {
            m_precededByTechDelimiter = false;
        }
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    const bool isVniDigitCandidate = (m_inputMethod == InputMethod::VNI && isAsciiDigit(codepoint) && m_tokenLen > 0 && !m_literalLock);
    if (!isAsciiAlpha(codepoint) && !isVniDigitCandidate) {
        if (isComposing()) {
            clearWordState();
        }
        m_afterDigit = isAsciiDigit(codepoint);
        m_precededByLeadingSlash = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    if (m_tokenLen == 0 && m_afterDigit) {
        m_literalLock = true;
    }

    wchar_t priorDisplayed[kMaxWordTokens]{};
    const int priorLen = m_displayedLen;
    for (int i = 0; i < priorLen; ++i) priorDisplayed[i] = m_displayed[i];

    const wchar_t ch = static_cast<wchar_t>(codepoint);
    const wchar_t lowerCh = toLowerAscii(ch);
    const bool isUpper = (ch >= L'A' && ch <= L'Z');

    // Prevent silent character truncation when a continuous token exceeds kMaxWordTokens - 1 (e.g. 80 consecutive 'b's)
    if (m_rawLen >= kMaxWordTokens - 1 || m_tokenLen >= kMaxWordTokens - 1) {
        clearWordState();
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    if (m_rawLen < kMaxWordTokens - 1) {
        m_rawWord[m_rawLen++] = ch;
        m_rawWord[m_rawLen] = 0;
    }

    bool consumedAsModifier = false;
    if (m_inputMethod == InputMethod::Telex && isAsciiAlpha(codepoint)) {
        consumedAsModifier = m7(ch, lowerCh, isUpper);
    } else if (m_inputMethod == InputMethod::VNI && isAsciiDigit(codepoint)) {
        consumedAsModifier = m8(ch);
    }

    if (!consumedAsModifier) {
        // Post-Coda / Post-Syllable Overflow Lock (parity with macOS shouldLockPostCodaOverflow):
        // If m_tokens has already formed a valid Vietnamese syllable with Vietnamese-specific shapes (đ, ă, â, ơ, ư),
        // toned ê/ô, or a cancelled vowel shape, and appending lowerCh to m_tokens would violate Vietnamese phonotactics,
        // lock the syllable stem and append ch to m_literalTail so the Vietnamese syllable is never reverted to raw ASCII!
        bool lockOverflowToTail = false;
        if (m_tokenLen >= 2 && m0()) {
            int vStartNow = -1, vEndNow = -1;
            bool hasCodaNow = false;
            m2(vStartNow, vEndNow, hasCodaNow);

            bool hasVnSpecific = m_shapeCancelledOnce || m_hasUndoSnapshot;
            for (int i = 0; i < m_tokenLen; ++i) {
                if (m_tokens[i].shape == 2 || m_tokens[i].shape == 3 || m_tokens[i].shape == 4 ||
                    (m_tokens[i].shape == 1 && m_tone != 0)) {
                    hasVnSpecific = true;
                    break;
                }
            }
            if (!hasCodaNow && m12(lowerCh)) {
                hasVnSpecific = false;
            }
            if (hasVnSpecific && m_tokenLen < kMaxWordTokens) {
                m_tokens[m_tokenLen++] = C0{ lowerCh, isUpper, 0 };
                int vS = -1, vE = -1;
                bool hC = false;
                m2(vS, vE, hC);
                bool validExtended = m0();
                --m_tokenLen;
                if (!validExtended) {
                    lockOverflowToTail = true;
                }
            }
        }

        if (lockOverflowToTail) {
            if (m_literalTailLen < kMaxWordTokens - 1) {
                m_literalTail[m_literalTailLen++] = ch;
                m_literalTail[m_literalTailLen] = 0;
            }
        } else {
            if (m_tokenLen < kMaxWordTokens) {
                m_tokens[m_tokenLen++] = C0{ lowerCh, isUpper, 0 };
            }
            m_lastToneKey = 0;
            m_lastShapeKey = 0;
            m_shapeCancelledOnce = false;
            m_hasUndoSnapshot = false;

            int vStart = -1, vEnd = -1;
            bool hasCoda = false;
            m2(vStart, vEnd, hasCoda);
            if (vStart != -1 && hasCoda) {
                for (int i = vStart; i < vEnd; ++i) {
                    if (m_tokens[i].baseLower == L'u' && m_tokens[i + 1].baseLower == L'o' &&
                        (m_tokens[i].shape == 2 || m_tokens[i + 1].shape == 2)) {
                        m_tokens[i].shape = 2;
                        m_tokens[i + 1].shape = 2;
                    }
                }
            }
        }
    }

    m_displayedLen = m6(m_displayed, kMaxWordTokens);
    return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
}

int32_t S0::feedBackspace() {
    if (!isComposing()) {
        m_afterDigit = false;
        m_precededByLeadingSlash = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    // Re-arm committed Vietnamese word when user presses Backspace immediately after Space ("gõ xong + Space + Backspace rồi thêm")
    if (m_armedAfterSpace && m_displayedLen == 0) {
        m_armedAfterSpace = false;
        m_hasUndoSnapshot = false;
        m_shapeCancelledOnce = false;
        m_tokenLen = m_undoTokenLen;
        for (int i = 0; i < m_tokenLen; ++i) {
            m_tokens[i] = m_undoTokens[i];
        }
        m_tone = m_undoTone;
        m_lastToneKey = m_undoLastToneKey;
        m_lastShapeKey = m_undoLastShapeKey;
        m_rawLen = m_undoRawLen;
        for (int i = 0; i < m_rawLen; ++i) {
            m_rawWord[i] = m_undoRawWord[i];
        }
        m_rawWord[m_rawLen] = 0;
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        m_lastBackspaces = 1;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::Replace);
    }

    wchar_t priorDisplayed[kMaxWordTokens]{};
    const int priorLen = m_displayedLen;
    for (int i = 0; i < priorLen; ++i) priorDisplayed[i] = m_displayed[i];

    // 0. If there is a literal tail (e.g. 'rônz' -> 'rôn', 'nhũngw' -> 'nhũng'), pop from literalTail first
    if (m_literalTailLen > 0) {
        --m_literalTailLen;
        m_literalTail[m_literalTailLen] = 0;
        if (m_rawLen > 0) {
            --m_rawLen;
            m_rawWord[m_rawLen] = 0;
        }
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 0b. If last action was a vowel-shape cancellation or 'z' tone clear, restore the saved undo snapshot
    if (m_hasUndoSnapshot) {
        m_hasUndoSnapshot = false;
        m_shapeCancelledOnce = false;
        m_tokenLen = m_undoTokenLen;
        for (int i = 0; i < m_tokenLen; ++i) {
            m_tokens[i] = m_undoTokens[i];
        }
        m_tone = m_undoTone;
        m_rawLen = m_undoRawLen;
        for (int i = 0; i < m_rawLen; ++i) {
            m_rawWord[i] = m_undoRawWord[i];
        }
        m_rawWord[m_rawLen] = 0;
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // If currently displaying raw fallback or literal lock, delete last character directly
    bool isRawFallback = (priorLen == m_rawLen);
    if (isRawFallback) {
        for (int i = 0; i < priorLen; ++i) {
            if (priorDisplayed[i] != m_rawWord[i]) {
                isRawFallback = false;
                break;
            }
        }
    }
    if (m_literalLock || isRawFallback) {
        if (m_rawLen > 0) {
            --m_rawLen;
            m_rawWord[m_rawLen] = 0;
        }
        if (m_tokenLen > 0) {
            --m_tokenLen;
        }
        if (m_tokenLen == 0) {
            clearWordState();
            return static_cast<int32_t>(Action::Reset);
        }
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // Apple-style semantic Backspace:
    // 1. First remove active tone
    if (m_tone != 0) {
        m_tone = 0;
        m_lastToneKey = 0;
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 2. Next remove vowel diacritic shapes (ă/â/ê/ô/ơ/ư -> a/e/o/u)
    bool hadVowelShape = false;
    for (int i = 0; i < m_tokenLen; ++i) {
        if (m_tokens[i].baseLower != L'd' && m_tokens[i].shape != 0) {
            m_tokens[i].shape = 0;
            hadVowelShape = true;
        }
    }
    if (hadVowelShape) {
        m_lastShapeKey = 0;
        m_uHornFromOwnW = false;
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 3. If more than 1 token remains, pop the last token
    if (m_tokenLen > 1) {
        --m_tokenLen;
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 4. Single token 'đ' -> 'd'
    if (m_tokenLen == 1 && m_tokens[0].baseLower == L'd' && m_tokens[0].shape == 4) {
        m_tokens[0].shape = 0;
        m_displayedLen = m6(m_displayed, kMaxWordTokens);
        m_rawLen = m_displayedLen;
        for (int i = 0; i <= m_displayedLen; ++i) m_rawWord[i] = m_displayed[i];
        return m9(priorDisplayed, priorLen, m_displayed, m_displayedLen);
    }

    // 5. Last single character deleted -> empty
    clearWordState();
    return static_cast<int32_t>(Action::Reset);
}

int32_t S0::commitWord() {
    if (m_displayedLen == 0) {
        m_armedAfterSpace = false;
        m_hasUndoSnapshot = false;
        m_lastBackspaces = 0;
        m_lastTextUtf8[0] = '\0';
        return static_cast<int32_t>(Action::PassThrough);
    }

    const bool canArmPostCommit = !m_literalLock && m_literalTailLen == 0 && !m1() && m0();
    C0 savedTokens[kMaxWordTokens]{};
    int savedTokenLen = m_tokenLen;
    int savedTone = m_tone;
    wchar_t savedLastToneKey = m_lastToneKey;
    wchar_t savedLastShapeKey = m_lastShapeKey;
    wchar_t savedRaw[kMaxWordTokens]{};
    int savedRawLen = m_rawLen;
    if (canArmPostCommit) {
        for (int i = 0; i < savedTokenLen; ++i) savedTokens[i] = m_tokens[i];
        for (int i = 0; i < savedRawLen; ++i) savedRaw[i] = m_rawWord[i];
        savedRaw[savedRawLen] = 0;
    }

    wchar_t rawLower[kMaxWordTokens]{};
    for (int i = 0; i < m_rawLen; ++i) rawLower[i] = toLowerAscii(m_rawWord[i]);

    if (m_smartBilingual && m_prevCollisionRawLen > 0 && m_prevCollisionDisplayedLen > 0) {
        wchar_t prevLower[16]{};
        for (int i = 0; i < m_prevCollisionRawLen; ++i) prevLower[i] = toLowerAscii(m_prevCollisionRaw[i]);
        bool isTurnHead = (m_prevCollisionRawLen == 4 && prevLower[0] == L't' && prevLower[1] == L'u' && prevLower[2] == L'r' && prevLower[3] == L'n');
        bool isSexHead = (m_prevCollisionRawLen == 3 && prevLower[0] == L's' && prevLower[1] == L'e' && prevLower[2] == L'x');
        if ((isTurnHead && f9(rawLower, m_rawLen)) || (isSexHead && f10(rawLower, m_rawLen))) {
            wchar_t combined[kMaxWordTokens]{};
            int cLen = 0;
            for (int i = 0; i < m_prevCollisionRawLen && cLen < kMaxWordTokens - 1; ++i) combined[cLen++] = m_prevCollisionRaw[i];
            if (cLen < kMaxWordTokens - 1) combined[cLen++] = L' ';
            for (int i = 0; i < m_rawLen && cLen < kMaxWordTokens - 1; ++i) combined[cLen++] = m_rawWord[i];
            combined[cLen] = 0;
            const int32_t retroBs = static_cast<int32_t>(m_prevCollisionDisplayedLen + 1 + m_displayedLen);
            char utf8Retro[kMaxUtf8Bytes]{};
            m10(combined, cLen, utf8Retro, kMaxUtf8Bytes);
            m_prevCollisionDisplayedLen = 0;
            m_prevCollisionRawLen = 0;
            m_inEnglishContext = true;
            m_lastWordWasSexLoanwordHead = false;
            clearWordState();
            m_lastBackspaces = retroBs;
            m_lastIsOverride = true;
            for (int i = 0; i < kMaxUtf8Bytes; ++i) {
                m_lastTextUtf8[i] = utf8Retro[i];
                if (utf8Retro[i] == '\0') break;
            }
            return static_cast<int32_t>(Action::Commit);
        }
    }

    const bool wasBilingualRestore = (m_smartBilingual && m4() && m1());
    wchar_t finalWord[kMaxWordTokens]{};
    const int finalLen = m6(finalWord, kMaxWordTokens);
    const int32_t bs = static_cast<int32_t>(m_displayedLen);

    wchar_t finalLower[kMaxWordTokens]{};
    bool hasNonAscii = false;
    for (int i = 0; i < finalLen; ++i) {
        if (finalWord[i] > 0x7F) hasNonAscii = true;
        finalLower[i] = toLowerAscii(finalWord[i]);
    }
    m_lastWordWasSexLoanwordHead = f7(finalLower, finalLen) || f7(rawLower, m_rawLen);
    if (hasNonAscii || f8(finalLower, finalLen)) {
        m_inEnglishContext = false;
    } else if ((m_smartBilingual && m4() && m1()) || (!m0() && finalLen >= 2) || f4(rawLower, m_rawLen) || f6(rawLower, m_rawLen)) {
        m_inEnglishContext = true;
    }

    bool isTurnOrSex = (m_rawLen == 4 && rawLower[0] == L't' && rawLower[1] == L'u' && rawLower[2] == L'r' && rawLower[3] == L'n') ||
                       (m_rawLen == 3 && rawLower[0] == L's' && rawLower[1] == L'e' && rawLower[2] == L'x');
    if (m_smartBilingual && isTurnOrSex && hasNonAscii && m_pendingBoundaryCp == ' ' && finalLen < 15 && m_rawLen < 15) {
        for (int i = 0; i < finalLen; ++i) m_prevCollisionDisplayed[i] = finalWord[i];
        m_prevCollisionDisplayed[finalLen] = 0;
        m_prevCollisionDisplayedLen = finalLen;
        for (int i = 0; i < m_rawLen; ++i) m_prevCollisionRaw[i] = m_rawWord[i];
        m_prevCollisionRaw[m_rawLen] = 0;
        m_prevCollisionRawLen = m_rawLen;
    } else {
        m_prevCollisionDisplayedLen = 0;
        m_prevCollisionRawLen = 0;
    }

    char utf8Final[kMaxUtf8Bytes]{};
    m10(finalWord, finalLen, utf8Final, kMaxUtf8Bytes);

    clearWordState();
    if (canArmPostCommit) {
        m_armedAfterSpace = true;
        m_undoTokenLen = savedTokenLen;
        for (int i = 0; i < savedTokenLen; ++i) m_undoTokens[i] = savedTokens[i];
        m_undoTone = savedTone;
        m_undoLastToneKey = savedLastToneKey;
        m_undoLastShapeKey = savedLastShapeKey;
        m_undoRawLen = savedRawLen;
        for (int i = 0; i < savedRawLen; ++i) m_undoRawWord[i] = savedRaw[i];
        m_undoRawWord[savedRawLen] = 0;
    }
    m_lastBackspaces = bs;
    m_lastIsOverride = wasBilingualRestore;
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        m_lastTextUtf8[i] = utf8Final[i];
        if (utf8Final[i] == '\0') break;
    }
    return static_cast<int32_t>(Action::Commit);
}



static_assert(sizeof(S0) <= 4096, "S0 exceeds m_opaqueState buffer");

inline S0 *getImpl(uint8_t *buf) {
    return reinterpret_cast<S0 *>(buf);
}

inline void syncOut(WindowsNativeEngine *pub, S0 *impl, int32_t &outBs, char *outUtf8, bool &outComp) {
    (void)pub;
    outBs = impl->m_lastBackspaces;
    for (int i = 0; i < kMaxUtf8Bytes; ++i) {
        outUtf8[i] = impl->m_lastTextUtf8[i];
        if (impl->m_lastTextUtf8[i] == '\0') break;
    }
    outComp = impl->isComposing();
}

} // namespace

WindowsNativeEngine::WindowsNativeEngine() {
    clearWordState();
}

void WindowsNativeEngine::reset() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inEnglishContext = false;
    impl->m_lastWordWasSexLoanwordHead = false;
    impl->m_precededByTechDelimiter = false;
    impl->m_afterDigit = false;
    impl->m_precededByLeadingSlash = false;
    impl->m_pendingBoundaryCp = 0;
    impl->m_prevCollisionDisplayedLen = 0;
    impl->m_prevCollisionRawLen = 0;
    clearWordState();
}

void WindowsNativeEngine::clearWordState() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    impl->clearWordState();
    m_composingFlag = false;
    m_lastBackspaces = 0;
    m_lastTextUtf8[0] = '\0';
}

void WindowsNativeEngine::setInputMethod(InputMethod method) {
    m_inputMethod = method;
    auto *impl = getImpl(m_opaqueState);
    impl->setInputMethod(method);
    m_composingFlag = impl->isComposing();
    m_lastBackspaces = impl->m_lastBackspaces;
    m_lastTextUtf8[0] = '\0';
}

int32_t WindowsNativeEngine::feedChar(uint32_t codepoint) {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    int32_t act = impl->feedChar(codepoint);
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_composingFlag);
    return act;
}

int32_t WindowsNativeEngine::feedBackspace() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    int32_t act = impl->feedBackspace();
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_composingFlag);
    return act;
}

int32_t WindowsNativeEngine::commitWord() {
    auto *impl = getImpl(m_opaqueState);
    impl->m_inputMethod = m_inputMethod;
    impl->m_smartBilingual = m_smartBilingual;
    impl->m_modernOrthography = m_modernOrthography;
    int32_t act = impl->commitWord();
    syncOut(this, impl, m_lastBackspaces, m_lastTextUtf8, m_composingFlag);
    return act;
}

} // namespace vielotus_win

#if defined(_WIN32)
#define VIELOTUS_CAPI_EXPORT extern "C" __declspec(dllexport)
#else
#define VIELOTUS_CAPI_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {

struct VieLotusNativeCapiSession {
    vielotus_win::S0 impl{};
    int32_t lastAction{0};
    int32_t postCommitBackspaceStep{0};
    char composingUtf8[vielotus_win::kMaxUtf8Bytes]{};
    char rawUtf8[vielotus_win::kMaxUtf8Bytes]{};
    char lastTextUtf8[vielotus_win::kMaxUtf8Bytes]{};

    void syncStrings() {
        vielotus_win::S0::m10(impl.m_displayed, impl.m_displayedLen, composingUtf8, vielotus_win::kMaxUtf8Bytes);
        vielotus_win::S0::m10(impl.m_rawWord, impl.m_rawLen, rawUtf8, vielotus_win::kMaxUtf8Bytes);
        for (int i = 0; i < vielotus_win::kMaxUtf8Bytes; ++i) {
            lastTextUtf8[i] = impl.m_lastTextUtf8[i];
            if (lastTextUtf8[i] == '\0') break;
        }
    }
};

inline VieLotusNativeCapiSession *asSession(void *ptr) {
    return reinterpret_cast<VieLotusNativeCapiSession *>(ptr);
}

} // namespace

VIELOTUS_CAPI_EXPORT void *vielotus_create_session(void) {
    auto *s = new VieLotusNativeCapiSession();
    s->impl.clearWordState();
    return s;
}

VIELOTUS_CAPI_EXPORT void vielotus_destroy_session(void *session) {
    delete asSession(session);
}

VIELOTUS_CAPI_EXPORT void vielotus_reset_session(void *session) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.clearWordState();
    s->impl.m_afterDigit = false;
    s->impl.m_precededByLeadingSlash = false;
    s->impl.m_prevCollisionDisplayedLen = 0;
    s->impl.m_prevCollisionRawLen = 0;
    s->lastAction = 4;
    s->postCommitBackspaceStep = 0;
    s->impl.m_lastIsOverride = false;
    s->syncStrings();
}

VIELOTUS_CAPI_EXPORT void vielotus_set_input_method(void *session, int32_t method) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.setInputMethod(method == 1 ? vielotus_win::InputMethod::VNI : vielotus_win::InputMethod::Telex);
    s->postCommitBackspaceStep = 0;
    s->syncStrings();
}

VIELOTUS_CAPI_EXPORT void vielotus_set_grammar_profile(void *session, int32_t profile) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_grammarProfile = (profile == 0) ? 0 : 1;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_get_grammar_profile(void *session) {
    auto *s = asSession(session);
    if (!s) return 1;
    return s->impl.m_grammarProfile;
}

VIELOTUS_CAPI_EXPORT void vielotus_set_smart_bilingual(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_smartBilingual = enabled;
}

VIELOTUS_CAPI_EXPORT void vielotus_set_modern_orthography(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_modernOrthography = enabled;
}

VIELOTUS_CAPI_EXPORT void vielotus_set_quick_telex(void *session, bool enabled) {
    auto *s = asSession(session);
    if (!s) return;
    s->impl.m_quickTelex = enabled;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_char(void *session, uint32_t codepoint) {
    auto *s = asSession(session);
    if (!s) return 0;
    s->postCommitBackspaceStep = 0;
    if (s->impl.m_displayedLen > 0 &&
        !vielotus_win::S0::m13(codepoint) &&
        !vielotus_win::isAsciiAlpha(codepoint) &&
        !(s->impl.m_inputMethod == vielotus_win::InputMethod::VNI && vielotus_win::isAsciiDigit(codepoint) && s->impl.m_tokenLen > 0 && !s->impl.m_literalLock)) {
        int32_t act = s->impl.commitWord();
        s->impl.m_afterDigit = vielotus_win::isAsciiDigit(codepoint);
        s->impl.m_precededByLeadingSlash = false;
        s->lastAction = act;
        s->syncStrings();
        return act;
    }
    int32_t act = s->impl.feedChar(codepoint);
    if (act == 3 && codepoint == ' ' && s->impl.m_armedAfterSpace) {
        s->postCommitBackspaceStep = 1;
    }
    s->lastAction = act;
    s->syncStrings();
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_commit_word(void *session) {
    auto *s = asSession(session);
    if (!s) return 0;
    s->postCommitBackspaceStep = 0;
    int32_t act = s->impl.commitWord();
    s->lastAction = act;
    s->syncStrings();
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_backspace(void *session) {
    auto *s = asSession(session);
    if (!s) return 0;
    if (s->impl.m_displayedLen == 0) {
        if (s->postCommitBackspaceStep == 1 && s->impl.m_armedAfterSpace) {
            s->postCommitBackspaceStep = 2;
            s->lastAction = 0;
            s->impl.m_lastBackspaces = 0;
            s->impl.m_lastTextUtf8[0] = '\0';
            s->syncStrings();
            return 0;
        }
        if (s->postCommitBackspaceStep == 2 && s->impl.m_armedAfterSpace) {
            s->postCommitBackspaceStep = 0;
            s->impl.m_armedAfterSpace = false;
            s->impl.m_tokenLen = (s->impl.m_undoTokenLen > 1) ? (s->impl.m_undoTokenLen - 1) : 0;
            for (int i = 0; i < s->impl.m_tokenLen; ++i) {
                s->impl.m_tokens[i] = s->impl.m_undoTokens[i];
            }
            s->impl.m_tone = s->impl.m_undoTone;
            s->impl.m_lastToneKey = s->impl.m_undoLastToneKey;
            s->impl.m_lastShapeKey = s->impl.m_undoLastShapeKey;
            s->impl.m_displayedLen = s->impl.m6(s->impl.m_displayed, vielotus_win::kMaxWordTokens);
            s->impl.m_rawLen = s->impl.m_displayedLen;
            for (int i = 0; i <= s->impl.m_displayedLen; ++i) {
                s->impl.m_rawWord[i] = s->impl.m_displayed[i];
            }
            s->impl.m_lastBackspaces = 1;
            s->impl.m_lastTextUtf8[0] = '\0';
            s->lastAction = 2;
            s->syncStrings();
            return 2;
        }
        s->postCommitBackspaceStep = 0;
        s->impl.m_armedAfterSpace = false;
        s->lastAction = 0;
        s->syncStrings();
        return 0;
    }
    int32_t act = s->impl.feedBackspace();
    s->lastAction = act;
    s->syncStrings();
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_key(void *session, uint32_t key_code, char char_code, uint32_t modifiers) {
    (void)modifiers;
    if (!session) return 0;
    if (key_code == 51 || key_code == 8) {
        return vielotus_feed_backspace(session);
    }
    if (char_code >= 32 && char_code < 127) {
        return vielotus_feed_char(session, static_cast<uint32_t>(static_cast<unsigned char>(char_code)));
    }
    return 0;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_feed_char_ex(void *session, uint32_t codepoint, int32_t *out_backspaces, const char **out_text) {
    int32_t act = vielotus_feed_char(session, codepoint);
    auto *s = asSession(session);
    if (!s) return act;
    if (out_backspaces) *out_backspaces = s->impl.m_lastBackspaces;
    if (out_text) *out_text = s->lastTextUtf8;
    return act;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_get_last_action(void *session) {
    auto *s = asSession(session);
    return s ? s->lastAction : 0;
}

VIELOTUS_CAPI_EXPORT int32_t vielotus_get_last_backspaces(void *session) {
    auto *s = asSession(session);
    return s ? s->impl.m_lastBackspaces : 0;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_last_text(void *session) {
    auto *s = asSession(session);
    return s ? s->lastTextUtf8 : "";
}

VIELOTUS_CAPI_EXPORT bool vielotus_get_last_is_override(void *session) {
    auto *s = asSession(session);
    return s ? s->impl.m_lastIsOverride : false;
}

VIELOTUS_CAPI_EXPORT bool vielotus_is_composing(void *session) {
    auto *s = asSession(session);
    return s ? (s->impl.m_displayedLen > 0) : false;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_composing_text(void *session) {
    auto *s = asSession(session);
    if (!s) return "";
    s->syncStrings();
    return s->composingUtf8;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_raw_text(void *session) {
    auto *s = asSession(session);
    if (!s) return "";
    s->syncStrings();
    return s->rawUtf8;
}

VIELOTUS_CAPI_EXPORT void vielotus_append_context(void *session, const char *context_word) {
    auto *s = asSession(session);
    if (!s || !context_word) return;
    if (context_word[0] == '\0') {
        s->impl.m_inEnglishContext = false;
        s->impl.m_lastWordWasSexLoanwordHead = false;
        s->impl.m_precededByTechDelimiter = false;
        s->impl.m_afterDigit = false;
        s->impl.m_precededByLeadingSlash = false;
        s->impl.m_pendingBoundaryCp = 0;
        s->impl.m_prevCollisionDisplayedLen = 0;
        s->impl.m_prevCollisionRawLen = 0;
        return;
    }
    vielotus_win::S0 temp = s->impl;
    temp.clearWordState();
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(context_word); *p; ++p) {
        temp.feedChar(static_cast<uint32_t>(*p));
    }
    temp.feedChar(static_cast<uint32_t>(' '));
    s->impl.m_inEnglishContext = temp.m_inEnglishContext;
    s->impl.m_lastWordWasSexLoanwordHead = temp.m_lastWordWasSexLoanwordHead;
    s->impl.m_precededByTechDelimiter = temp.m_precededByTechDelimiter;
    s->impl.m_prevCollisionDisplayedLen = 0;
    s->impl.m_prevCollisionRawLen = 0;
}

VIELOTUS_CAPI_EXPORT void vielotus_sync_armed_word(void *session, const char *before_context_utf8) {
    (void)session;
    (void)before_context_utf8;
}

VIELOTUS_CAPI_EXPORT const char *vielotus_get_version(void) {
    return "2.0.0";
}
