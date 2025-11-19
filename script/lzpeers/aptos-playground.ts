import { Aptos, AptosConfig, Network } from '@aptos-labs/ts-sdk'
import { aptosMovementOFTs } from './oft'
import { chains } from './chains'

interface Executor {
    executor_address: string;  // Address is a string
    max_message_size: number;  // Max message size is a number
}

interface ExecutorConfig {
    vec: Executor[];  // vec is an array of Executor objects
}

interface AppConfigEntry {
    confirmations: string;
    optional_dvn_threshold: number;
    optional_dvns: string[];
    required_dvns: string[];
    use_default_for_confirmations: boolean;
    use_default_for_optional_dvns: boolean;
    use_default_for_required_dvns: boolean;
}

interface AppConfig {
    vec: AppConfigEntry[];
}

async function main() {
    const aptos = new Aptos(
        new AptosConfig({
            network: Network.MAINNET,
            fullnode: 'https://fullnode.mainnet.aptoslabs.com/v1',
        })
    )

    const peerBytes32 = await aptos.view({
        payload: {
            function: `${aptosMovementOFTs['frxUSD'].oft}::oapp_core::get_peer`,
            functionArguments: [30255],
        },
    })
    console.log("peerBytes32 ", peerBytes32[0])

    const appExecutorConfig = await aptos.view({
        payload: {
            function: `${chains["aptos"].sendLib302}::msglib::get_app_executor_config`,
            functionArguments: [aptosMovementOFTs["frxUSD"].oft, 30255]
        }
    })

    console.log("appExecutorConfig : executor address ", (appExecutorConfig[0] as ExecutorConfig).vec[0].executor_address)
    console.log("appExecutorConfig : max message size ", (appExecutorConfig[0] as ExecutorConfig).vec[0].max_message_size)

    const defaultExecutorConfig = await aptos.view({
        payload: {
            function: `${chains["aptos"].sendLib302}::msglib::get_default_executor_config`,
            functionArguments: [30255]
        }
    })

    console.log("defaultExecutorConfig : executor address ", (defaultExecutorConfig[0] as ExecutorConfig).vec[0].executor_address)
    console.log("defaultExecutorConfig : max message size ", (defaultExecutorConfig[0] as ExecutorConfig).vec[0].max_message_size)

    const appReceiveConfig = await aptos.view({
        payload: {
            function: `${chains["aptos"].sendLib302}::msglib::get_app_receive_config`,
            functionArguments: [aptosMovementOFTs["frxUSD"].oft, 30255]
        }
    })

    console.log("appReceiveConfig : confirmations ", (appReceiveConfig[0] as AppConfig).vec[0].confirmations)
    console.log("appReceiveConfig : optional_dvn_threshold ", (appReceiveConfig[0] as AppConfig).vec[0].optional_dvn_threshold)
    console.log("appReceiveConfig : optional_dvns ", (appReceiveConfig[0] as AppConfig).vec[0].optional_dvns)
    console.log("appReceiveConfig : required_dvns ", (appReceiveConfig[0] as AppConfig).vec[0].required_dvns)
    console.log("appReceiveConfig : use_default_for_confirmations ", (appReceiveConfig[0] as AppConfig).vec[0].use_default_for_confirmations)
    console.log("appReceiveConfig : use_default_for_optional_dvns ", (appReceiveConfig[0] as AppConfig).vec[0].use_default_for_optional_dvns)
    console.log("appReceiveConfig : use_default_for_required_dvns ", (appReceiveConfig[0] as AppConfig).vec[0].use_default_for_required_dvns)

    const appSendConfig = await aptos.view({
        payload: {
            function: `${chains["aptos"].sendLib302}::msglib::get_app_send_config`,
            functionArguments: [aptosMovementOFTs["frxUSD"].oft, 30255]
        }
    })

    console.log("appSendConfig : confirmations ", (appSendConfig[0] as AppConfig).vec[0].confirmations)
    console.log("appSendConfig : optional_dvn_threshold ", (appSendConfig[0] as AppConfig).vec[0].optional_dvn_threshold)
    console.log("appSendConfig : optional_dvns ", (appSendConfig[0] as AppConfig).vec[0].optional_dvns)
    console.log("appSendConfig : required_dvns ", (appSendConfig[0] as AppConfig).vec[0].required_dvns)
    console.log("appSendConfig : use_default_for_confirmations ", (appSendConfig[0] as AppConfig).vec[0].use_default_for_confirmations)
    console.log("appSendConfig : use_default_for_optional_dvns ", (appSendConfig[0] as AppConfig).vec[0].use_default_for_optional_dvns)
    console.log("appSendConfig : use_default_for_required_dvns ", (appSendConfig[0] as AppConfig).vec[0].use_default_for_required_dvns)

    // 0xe067037681385b86d8344e6b7746023604c6ac90ddc997ba3c58396c258ad17b

    const defaultUlnReceiveConfig = await aptos.view({
        payload: {
            function: `${chains["aptos"].sendLib302}::msglib::get_default_uln_receive_config`,
            functionArguments: [30255]
        }
    })

    console.log("defaultUlnReceiveConfig : confirmations ", (defaultUlnReceiveConfig[0] as AppConfig).vec[0].confirmations)
    console.log("defaultUlnReceiveConfig : optional_dvn_threshold ", (defaultUlnReceiveConfig[0] as AppConfig).vec[0].optional_dvn_threshold)
    console.log("defaultUlnReceiveConfig : optional_dvns ", (defaultUlnReceiveConfig[0] as AppConfig).vec[0].optional_dvns)
    console.log("defaultUlnReceiveConfig : required_dvns ", (defaultUlnReceiveConfig[0] as AppConfig).vec[0].required_dvns)
    console.log("defaultUlnReceiveConfig : use_default_for_confirmations ", (defaultUlnReceiveConfig[0] as AppConfig).vec[0].use_default_for_confirmations)
    console.log("defaultUlnReceiveConfig : use_default_for_optional_dvns ", (defaultUlnReceiveConfig[0] as AppConfig).vec[0].use_default_for_optional_dvns)
    console.log("defaultUlnReceiveConfig : use_default_for_required_dvns ", (defaultUlnReceiveConfig[0] as AppConfig).vec[0].use_default_for_required_dvns)

    const defaultUlnSendConfig = await aptos.view({
        payload: {
            function: `${chains["aptos"].sendLib302}::msglib::get_default_uln_send_config`,
            functionArguments: [30255]
        }
    })

    console.log("defaultUlnSendConfig : confirmations ", (defaultUlnSendConfig[0] as AppConfig).vec[0].confirmations)
    console.log("defaultUlnSendConfig : optional_dvn_threshold ", (defaultUlnSendConfig[0] as AppConfig).vec[0].optional_dvn_threshold)
    console.log("defaultUlnSendConfig : optional_dvns ", (defaultUlnSendConfig[0] as AppConfig).vec[0].optional_dvns)
    console.log("defaultUlnSendConfig : required_dvns ", (defaultUlnSendConfig[0] as AppConfig).vec[0].required_dvns)
    console.log("defaultUlnSendConfig : use_default_for_confirmations ", (defaultUlnSendConfig[0] as AppConfig).vec[0].use_default_for_confirmations)
    console.log("defaultUlnSendConfig : use_default_for_optional_dvns ", (defaultUlnSendConfig[0] as AppConfig).vec[0].use_default_for_optional_dvns)
    console.log("defaultUlnSendConfig : use_default_for_required_dvns ", (defaultUlnSendConfig[0] as AppConfig).vec[0].use_default_for_required_dvns)

    const enforcedOptions = await aptos.view({
        payload: {
            function: `${aptosMovementOFTs["frxUSD"].oft}::oapp_core::get_enforced_options`,
            functionArguments: [30255, 1],


        }
    })

    console.log(enforcedOptions)

}

main()
