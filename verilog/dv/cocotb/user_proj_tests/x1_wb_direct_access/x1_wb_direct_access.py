from caravel_cocotb.caravel_interfaces import test_configure
from caravel_cocotb.caravel_interfaces import report_test
import cocotb


@cocotb.test()
@report_test
async def x1_wb_direct_access(dut):
    caravelEnv = await test_configure(dut, timeout_cycles=300000)
    cocotb.log.info("[TEST] Start x1_wb_direct_access")
    await caravelEnv.release_csb()
    await caravelEnv.wait_mgmt_gpio(1)
    cocotb.log.info("[TEST] Direct X1 WB access passed")
