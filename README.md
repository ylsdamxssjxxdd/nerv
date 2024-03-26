# nerv
快速的大模型训练容器：总部 (docker+llama-factory)

## 目标
- 量产
    - 破坏模型的人性得到机性：由于训练全知全能的大模型代价太大，可行性不高，计划先将开源的对话模型微调为专门用于执行特定任务的puppet（傀儡）模型
- 补完
    - 破坏模型的人性、机性得到神性：通过收集对话模型和傀儡模型的数据，恢复和提升预训练模型，不断迭代实现补完
    - 预训练模型（神性）<->对话模型（人性）<->傀儡模型（机性）
## 特定任务
- 工具调用（智能体）
- 私有知识
- 固定格式

## 运行必须
- 总部项目文件 
```bash
git clone https://github.com/ylsdamxssjxxdd/nerv.git
```
- 总部镜像文件 施工中...
- nvidia-docker运行环境

## 训练要素
- 数据集
- 原始模型
- 训练方式


