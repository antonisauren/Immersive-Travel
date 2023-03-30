use std::path::Path;

use mwscript::dump_scripts;

#[test]
fn test_dump() -> std::io::Result<()> {
    let input = Path::new("tests/assets/Ashlander Crafting.ESP");
    let output = Path::new("tests/assets/out");

    assert!(
        dump_scripts(&Some(input.into()), Some(output.into())).is_ok(),
        "error converting"
    );

    Ok(())
}
